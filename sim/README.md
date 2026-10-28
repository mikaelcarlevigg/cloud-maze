# Cloud Maze, lokal simulering

Prova Cloud Maze på din egen dator. Du behöver inget AWS-konto och inga extra paket, bara Python 3.9 eller senare.

Simuleringen bygger samma logik som konceptet i [huvud-README:n](../README.md): en tjänst vars väg flyttas, en kartjänst för behöriga, och snubbeltrådar som larmar när någon använder en gammal väg.

## Bara en mobil?

Öppna `web.html` i webbläsaren. Den kör samma logik direkt i sidan, och du spelar angripare med knappar.

## Kom igång

Hämta repot och gå till mappen:

```bash
git clone https://github.com/mikaelcarlevigg/cloud-maze.git
cd cloud-maze/sim
```

### 1. Se hela förloppet på 20 sekunder

```bash
python3 demo.py
```

Demon kör en behörig klient och en angripare mot samma labyrint och berättar vad som händer:

```
    0.0 s  MOTOR      första vägen är ed3c7e
    1.0 s  ANGRIPARE  hittar väg ed3c7e i en läckt logg och sparar den
    4.0 s  MOTOR      öppnar ny väg 8a8488 och publicerar kartan
    4.4 s  KLIENT     använder väg 8a8488 enligt kartan, fick ordrarna
    5.5 s  MOTOR      stänger ed3c7e, den är nu en snubbeltråd
    8.8 s  LARM       gammal väg använd: ed3c7e
    8.8 s  SPÅRNING   vägen ed3c7e fanns bara 0.0 s till 5.5 s, så läckan skedde då
    8.8 s  ANGRIPARE  angriper via ed3c7e: svar 200, {"orders": []}
    ...
Resultat
  Behörig klient:   79 av 79 anrop lyckades, 0 misslyckades, bytte väg 4 gånger
  Larm:             3, varav 0 falsklarm
  Angriparen:       fick 0 ordrar via gamla vägar och lockbeten
```

Lägg märke till tre saker:

- **Klienten märker ingenting.** Den byter väg varje gång kartan uppdateras, och inget anrop misslyckas.
- **Angriparen luras.** Den gamla vägen svarar som vanligt men ger inga ordrar, så angriparen vet inte att den är upptäckt.
- **Läckan går att spåra.** Larmet visar exakt när den stulna vägen fanns, vilket pekar ut när informationen läckte.

Du kan ändra takten, till exempel `python3 demo.py --interval 6 --overlap 2 --duration 30`.

### 2. Var angriparen själv

Starta servern i ett terminalfönster:

```bash
python3 server.py
```

Servern skriver ut vägen som gäller just nu och ett kommando för att starta en behörig klient. Kör det kommandot i ett andra fönster. Klienten anropar tjänsten varje sekund och visar när den byter väg.

Spela sedan angripare i ett tredje fönster:

1. Kopiera vägen servern visar just nu och kör `curl` mot den. Du får ordrarna.
2. Vänta tills servern skriver `STÄNGD` för just den vägen. Det tar runt 25 sekunder med standardinställningarna.
3. Kör samma `curl` igen. Du får ett tomt svar, och servern skriver `LARM`.
4. Prova också en av vägarna under `Lockbeten`, eller `curl http://127.0.0.1:8080/map` utan nycklar.

Klienten i det andra fönstret fortsätter fungera hela tiden.

### 3. Kör testerna

```bash
python3 -m unittest -v
```

Testerna kontrollerar labyrintens tre regler: att det alltid finns en öppen väg, att en behörig klient aldrig misslyckas när vägen flyttas, och att gamla vägar och lockbeten larmar.

## Vad varje fil motsvarar i AWS

| Fil | Gör | I AWS |
| --- | --- | --- |
| `maze.py`, klassen `Maze` | Håller reda på öppna, stängda och falska vägar | DynamoDB |
| `maze.py`, klassen `Engine` | Flyttar vägen i fyra steg: öppna, publicera, vänta, stäng | EventBridge Scheduler och Step Functions |
| `server.py`, `/v1/<väg>/orders` | Tjänsten bakom den roterande vägen | CloudFront, AWS WAF och API Gateway |
| `server.py`, `/map` | Kartjänsten, bara för behöriga | API Gateway med mTLS eller SigV4 |
| `server.py`, signering av kartan | Gör att en förfalskad karta upptäcks | AWS KMS |
| `server.py`, larmen | Snubbeltrådar och lockbeten | Lambda, CloudWatch och Security Hub |
| `client.py` | Hämtar kartan, kontrollerar signaturen, byter väg i tid | Klientbiblioteket |

## Förenklingar

Simuleringen visar idén, men den är inte säker att använda på riktigt:

- Klienter och kartsignering använder delade hemliga nycklar (HMAC). I AWS skulle klienter identifiera sig med certifikat eller IAM, och KMS skulle signera kartan med en asymmetrisk nyckel.
- Tjänsten saknar egen inloggning. I verkligheten är Cloud Maze ett lager ovanpå vanlig autentisering, inte en ersättning för den.
- Allt körs i en process på en dator, och labyrintens tillstånd försvinner när servern stängs.
- Bara adressen flyttas. Nycklar och tillåtna källadresser roterar inte än.
