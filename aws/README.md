# Cloud Maze i AWS, fas 1

Den här versionen körs på riktigt i ett AWS-konto. Du kan installera och testa den med bara en mobil, utan att skriva några kommandon.

Allt installeras i ditt eget konto, och bara du får API-adressen. Vill någon annan prova installerar de i sitt eget AWS-konto på samma sätt.

## Det här byggs

| Del | AWS-tjänst | Gör |
| --- | --- | --- |
| Labyrintmotorn | EventBridge och Lambda (`rotator`) | Flyttar tjänstens väg varannan minut. En väg lever i två intervall, varav det sista är överlapp. |
| Labyrintens tillstånd | DynamoDB | Aktuell väg, föregående väg, stängda vägar och lockbeten |
| Tjänsten | API Gateway och Lambda (`service`) | `GET /v1/<väg>/orders`. Öppen väg ger ordrar. Stängd väg eller lockbete ger ett tomt svar och ett larm. |
| Kartjänsten | Lambda (`map`) | Ger aktuell väg. Den nås bara med din IAM-identitet, aldrig från internet. |
| Larmen | SNS | Mejlar dig när någon använder en gammal väg eller ett lockbete, med tidsfönstret som visar när vägen läckte |
| Kontrollpanelen | API Gateway och Lambda (`panel`) | En webbsida för mobilen med hemlig adress. Visar aktuell väg, gamla vägar och ett lockbete som du trycker på för att testa. |

## Kostnad och säkerhetsspärrar

Inget ska dra pengar i det tysta. Därför finns de här spärrarna:

1. **Labyrinten stänger av sig själv efter 2 timmar.** Motorn slutar flytta vägen, API:et börjar avvisa alla anrop, och du får ett mejl om det.
2. **API:et är strypt till 2 anrop per sekund.** Även om någon skulle hitta adressen och hamra på den kan det inte bli många anrop.
3. **Budgetlarm, som du lägger till själv.** Det går inte att skapa från mallen i alla regioner. Gå till **Billing and Cost Management**, välj **Budgets**, tryck **Create budget** och välj mallen **Zero spend budget**. Fyll i din e-post och tryck **Create budget**. Du får då ett mejl så fort kontot kostar något alls. Budgetlarm uppdateras några gånger per dygn, så det fungerar som ett skyddsnät, inte som en spärr.
4. **`./destroy.sh` tar bort allt.** Kör det när du är klar.

Alla delar betalas per användning, och en testrunda gör bara några hundra anrop. Kostnaden blir därför i praktiken noll. Lambda och API Gateway har dessutom gratisnivåer. När du skapar ett nytt AWS-konto kan du få välja en gratisplan med startkrediter, där kontot inte debiteras alls. Kontrollera vad som gäller när du registrerar dig.

## Installera från mobilen utan att skriva kommandon

Allt görs med knappar i AWS-konsolen. Det enda du skriver är ett stacknamn och din e-postadress.

### 1. Skapa ett AWS-konto

Gå till https://aws.amazon.com och välj att skapa ett konto. Du behöver en e-postadress, ett betalkort och telefonen för verifiering. Välj gratisplanen om du får frågan.

### 2. Ladda ner mallen till mobilen

Håll fingret på den här länken och välj **Ladda ned länkad fil**:

https://github.com/mikaelcarlevigg/cloud-maze/raw/main/aws/template.yaml

Filen hamnar i mappen Hämtade filer.

### 3. Installera med CloudFormation

1. Logga in på https://console.aws.amazon.com och välj region uppe till höger, till exempel **Europe (Stockholm)**.
2. Öppna tjänsten **CloudFormation** (sök på "cloud" i sökfältet).
3. Tryck **Create stack** och välj **With new resources**.
4. Välj **Upload a template file**, tryck **Choose file** och välj `template.yaml` från Hämtade filer. Tryck **Next**.
5. Skriv `cm` som **Stack name** och din e-postadress under **AlarmEmail**. Låt resten vara. Tryck **Next**.
6. Tryck **Next** igen på nästa sida.
7. Längst ner: kryssa i rutan **I acknowledge that AWS CloudFormation might create IAM resources** och tryck **Submit**.
8. Vänta tills stacken visar **CREATE_COMPLETE**. Det tar 2–3 minuter. Dra ner för att uppdatera.

### 4. Bekräfta larmen

Öppna mejlet från AWS Notifications och tryck på **Confirm subscription**. Annars kommer inga larm fram.

### 5. Testa i kontrollpanelen

Gå till fliken **Outputs** på stacken och tryck på länken vid **PanelUrl**. Spara gärna sidan som bokmärke. Adressen innehåller stackens unika id, så bara du hittar den.

Panelen uppdateras var 15:e sekund och har tre delar:

- **Behörig klient:** visar vägen som kartan anger just nu. Tryck på den: du får ordrarna. Vänta två minuter och se att vägen har bytts.
- **Gamla vägar:** när den första vägen har stängts, efter cirka fyra minuter, dyker den upp här. Tryck på den: svaret ser normalt ut men är tomt, och du får ett larmmejl. Mejlet visar mellan vilka klockslag vägen fanns, alltså när den läckte.
- **Lockbete:** en väg som aldrig har funnits på någon karta. Tryck på den och kolla mejlen.

Gå tillbaka till panelen med webbläsarens bakåtknapp.

### 6. Ta bort allt

I CloudFormation: välj stacken `cm` och tryck **Delete**. Allt som installerades tas bort.

## Installera med kommandon i CloudShell

Föredrar du kommandon kan du installera från AWS CloudShell, terminalfönstret i AWS-konsolen. Då får du också en behörig klient och angriparskript som körs i terminalen.

### Öppna CloudShell

1. Logga in på https://console.aws.amazon.com.
2. Välj region uppe till höger, till exempel **Europe (Stockholm)**.
3. Sök efter **CloudShell** i sökfältet högst upp och öppna det. Första gången tar det någon minut att starta.

Det går ofta inte att klistra in i CloudShell på en mobil. Därför behöver du bara skriva två korta rader. Resten sköter du med siffror i en meny.

### Hämta koden och starta menyn

Skriv de här två raderna och tryck Enter efter var och en:

```bash
git clone https://github.com/mikaelcarlevigg/cloud-maze
cloud-maze/cm
```

Menyn ser ut så här:

```
========== Cloud Maze ==========
Status: inte installerad

  1  Installera
  2  Kör behörig klient (6 min)
  3  Angripare: stjäl vägen som gäller nu
  4  Angripare: angrip med stulen väg
  5  Angripare: prova lockbete
  6  Angripare: gissa en väg
  7  Ta bort allt
  0  Avsluta menyn
```

Kommer du tillbaka senare, eller har CloudShell startats om, skriver du bara `cloud-maze/cm` igen.

### Testa från menyn

1. **Välj 1** och skriv din e-postadress. Installationen tar ett par minuter.
2. **Öppna mejlet från AWS Notifications och tryck på *Confirm subscription*.** Annars kommer inga larm fram.
3. **Välj 2.** Den behöriga klienten hämtar kartan med din IAM-identitet och anropar tjänsten var tionde sekund i sex minuter. Du ser hur den byter väg varannan minut utan att något anrop misslyckas.
4. **Välj 3.** Du stjäl vägen som gäller just nu, som om den hade läckt i en logg. Den fungerar, du får ordrarna.
5. **Vänta 4–5 minuter.** Menyn visar *STÄNGD* när den stulna vägen har stängts.
6. **Välj 4.** Svaret ser normalt ut men innehåller inga ordrar. Kolla din e-post: där ligger ett larm som talar om vilken väg som användes, varifrån anropet kom, och mellan vilka klockslag vägen fanns. Det är där läckan skedde.
7. **Välj 5 och 6.** Ett lockbete larmar på samma sätt. En gissad väg ger bara 404 och inget larm.
8. **Välj 7** när du är klar. Det tar bort allt som installerades.

Du kan också öppna den stulna adressen i mobilens webbläsare. Den skrivs ut när du väljer 3.

Föredrar du kommandon framför menyn finns skripten `deploy.sh`, `client.sh`, `attacker.sh` och `destroy.sh` i samma mapp.

## Egna inloggningsuppgifter

Allt installeras i det AWS-konto du är inloggad i. Hur du loggar in beror på var du kör:

- **CloudFormation-konsolen** (installationen med knappar ovan): du är inloggad via webbläsaren. Inga nycklar behövs.
- **AWS CloudShell:** du är redan inloggad som den användare du loggade in i konsolen med. Inga nycklar behövs.
- **Din egen dator:** installera [AWS CLI](https://aws.amazon.com/cli/). Har du redan kört `aws configure` används de uppgifterna. Annars frågar skripten efter dina nycklar när du startar dem.

Nycklar som du skriver in när skripten frågar gäller bara så länge skriptet körs. De sparas aldrig på disk eller i repot. Ditt hemliga värde syns inte när du skriver.

Innan något installeras visar skriptet vilket konto och vilken region det gäller, och du måste skriva `j` för att fortsätta. Om ingen region är vald föreslås `eu-north-1` (Stockholm). Klienten och angriparskripten kontrollerar dessutom att du är inloggad i samma konto som labyrinten installerades i.

### Så skapar du nycklar

1. Logga in i AWS-konsolen och öppna **IAM**.
2. Välj **Users** och **Create user**. Använd inte root-användarens nycklar.
3. Ge användaren behörighet. För ett test är **AdministratorAccess** enklast, eftersom stacken skapar roller, funktioner, en tabell och ett API.
4. Öppna användaren, gå till **Security credentials** och välj **Create access key** med användningsområdet **Command Line Interface (CLI)**.
5. Spara **Access key ID** och **Secret access key**. Det hemliga värdet visas bara en gång.

Ta bort nyckeln, eller hela användaren, när du har testat klart. Lägg aldrig nycklar i kod, i repot eller i chattar.

Har du tillfälliga nycklar, till exempel från AWS IAM Identity Center, fyller du också i **session token** när skriptet frågar.

## Inställningar

```bash
./deploy.sh din@epost.se 5     # flytta vägen var 5:e minut i stället för varannan
```

Hur länge labyrinten körs (`RunHours`) väljer du när du skapar stacken, eller i `template.yaml`. Labyrinten startar inte om av sig själv efter att den har stängts av. Kör `./destroy.sh` och sedan `./deploy.sh` igen.

## Skillnader mot konceptet

Fas 1 visar kärnan: vägen flyttas med överlapp, behöriga hittar rätt via kartan, och gamla vägar och lockbeten larmar. Det här saknas än:

- **Väg-kontrollen görs i Lambda.** I konceptet stoppar CloudFront och WAF gamla vägar redan vid kanten.
- **Kartan är inte signerad.** IAM skyddar den, men KMS-signering ingår inte än.
- **Bara adressen flyttas.** Nycklar och tillåtna källadresser roterar inte.
- **Tjänsten saknar egen inloggning.** I verkligheten är Cloud Maze ett lager ovanpå vanlig autentisering.
- **Larmen kan bli många.** Varje träff på en snubbeltråd ger ett mejl. Strypningen håller nere antalet, men en riktig version skulle samla larmen i Security Hub.
