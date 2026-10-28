# Cloud Maze i AWS, fas 1

Den här versionen körs på riktigt i ett AWS-konto. Du kan installera och testa den med bara en mobil, eftersom allt görs i AWS CloudShell, ett terminalfönster som finns inbyggt i AWS-konsolen i webbläsaren.

Allt installeras i ditt eget konto, och bara du får API-adressen. Vill någon annan prova installerar de i sitt eget AWS-konto på samma sätt.

## Det här byggs

| Del | AWS-tjänst | Gör |
| --- | --- | --- |
| Labyrintmotorn | EventBridge och Lambda (`rotator`) | Flyttar tjänstens väg varannan minut. En väg lever i två intervall, varav det sista är överlapp. |
| Labyrintens tillstånd | DynamoDB | Aktuell väg, föregående väg, stängda vägar och lockbeten |
| Tjänsten | API Gateway och Lambda (`service`) | `GET /v1/<väg>/orders`. Öppen väg ger ordrar. Stängd väg eller lockbete ger ett tomt svar och ett larm. |
| Kartjänsten | Lambda (`map`) | Ger aktuell väg. Den nås bara med din IAM-identitet, aldrig från internet. |
| Larmen | SNS | Mejlar dig när någon använder en gammal väg eller ett lockbete, med tidsfönstret som visar när vägen läckte |
| Budgetlarm | AWS Budgets | Mejlar dig om kontots kostnad når halva månadsbudgeten |

## Kostnad och säkerhetsspärrar

Inget ska dra pengar i det tysta. Därför finns fyra spärrar:

1. **Labyrinten stänger av sig själv efter 2 timmar.** Motorn slutar flytta vägen, API:et börjar avvisa alla anrop, och du får ett mejl om det.
2. **API:et är strypt till 2 anrop per sekund.** Även om någon skulle hitta adressen och hamra på den kan det inte bli många anrop.
3. **Budgetlarm.** Du får ett mejl om kontots kostnad når 0,50 USD under månaden. Budgetlarm uppdateras några gånger per dygn, så det fungerar som ett skyddsnät, inte som en spärr.
4. **`./destroy.sh` tar bort allt.** Kör det när du är klar.

Alla delar betalas per användning, och en testrunda gör bara några hundra anrop. Kostnaden blir därför i praktiken noll. Lambda och API Gateway har dessutom gratisnivåer. När du skapar ett nytt AWS-konto kan du få välja en gratisplan med startkrediter, där kontot inte debiteras alls. Kontrollera vad som gäller när du registrerar dig.

## Installera från mobilen

### 1. Skapa ett AWS-konto

Gå till https://aws.amazon.com och välj att skapa ett konto. Du behöver en e-postadress, ett betalkort och telefonen för verifiering. Välj gratisplanen om du får frågan.

### 2. Öppna CloudShell

1. Logga in på https://console.aws.amazon.com.
2. Välj region uppe till höger, till exempel **Europe (Stockholm)**.
3. Sök efter **CloudShell** i sökfältet högst upp och öppna det. Första gången tar det någon minut att starta.

Det går ofta inte att klistra in i CloudShell på en mobil. Därför behöver du bara skriva två korta rader. Resten sköter du med siffror i en meny.

### 3. Hämta koden och starta menyn

Skriv de här två raderna och tryck Enter efter var och en:

```bash
git clone https://github.com/mikaelcarlevigg/cloud-maze
cloud-maze/cm
```

`git clone` hämtar koden från `main`. Om pull requesten med Cloud Maze inte är inslagen än, lägg till grenens namn: `git clone -b claude/cloud-maze-concept-xvvzwy https://github.com/mikaelcarlevigg/cloud-maze`.

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

### 4. Testa

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

## Inställningar

```bash
./deploy.sh din@epost.se 5     # flytta vägen var 5:e minut i stället för varannan
```

Hur länge labyrinten körs (`RunHours`) och månadsbudgeten (`BudgetUsd`) ställer du in i `template.yaml`. Labyrinten startar inte om av sig själv efter att den har stängts av. Kör `./destroy.sh` och sedan `./deploy.sh` igen.

## Skillnader mot konceptet

Fas 1 visar kärnan: vägen flyttas med överlapp, behöriga hittar rätt via kartan, och gamla vägar och lockbeten larmar. Det här saknas än:

- **Väg-kontrollen görs i Lambda.** I konceptet stoppar CloudFront och WAF gamla vägar redan vid kanten.
- **Kartan är inte signerad.** IAM skyddar den, men KMS-signering ingår inte än.
- **Bara adressen flyttas.** Nycklar och tillåtna källadresser roterar inte.
- **Tjänsten saknar egen inloggning.** I verkligheten är Cloud Maze ett lager ovanpå vanlig autentisering.
- **Larmen kan bli många.** Varje träff på en snubbeltråd ger ett mejl. Strypningen håller nere antalet, men en riktig version skulle samla larmen i Security Hub.
