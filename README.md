# Cloud Maze

**Your API moves every few minutes. Authorized clients follow a map. Attackers walk into a maze.**

Cloud Maze is an open-source prototype of *moving target defense* on AWS. The address of an API keeps rotating, every old address becomes a tripwire that shows when it leaked, and whoever uses one ends up in a shadow world of fake data, followed by a marked key that gives them away on any IP address.

<p align="center">
  <a href="https://mikaelcarlevigg.github.io/cloud-maze/sim/web.html">
    <img src="docs/images/simulator.png" width="320" alt="The Cloud Maze simulator: the current path, a stolen path that has closed, an authorized client with 19 of 19 requests succeeding, and two alarms that show when the paths leaked.">
  </a>
  <br>
  <sub>The simulator. Tap the image to play the attacker in your browser.</sub>
</p>

<p align="center">
  <img src="docs/images/panel.png" width="320" alt="The control panel of the AWS version: the current path, two closed paths with the times they existed, a decoy, two IP addresses in the shadow world and a marked key.">
  <br>
  <sub>The control panel of the AWS version, rendered from its own code with test data and documentation IP addresses.</sub>
</p>

<!--
  Room for a screenshot of an alarm e-mail from a real install. Save it as
  docs/images/alarm-email.png, crop away the unsubscribe link (it shows the
  AWS account number), and add it here.
-->

## Try it

| How | Time | What you need |
| --- | --- | --- |
| [**Play the attacker in your browser**](https://mikaelcarlevigg.github.io/cloud-maze/sim/web.html) | 1 minute | Nothing |
| [**Install it in your own AWS account**](aws/README.md) | 5 minutes | An AWS account. Works from a phone. |
| [**Run the simulation locally**](sim/README.md) | 1 minute | Python 3.9 or later |

The AWS version shuts itself down after two hours and costs practically nothing to try.

## What it does

- **The path rotates.** `/v1/k7f2q9/orders` becomes `/v1/m3x8a1/orders` on a schedule. Authorized clients fetch a map through IAM, and an overlap keeps both paths open while they switch, so nobody gets locked out.
- **Old paths become tripwires.** Authorized clients never use them, so a hit is a strong signal. The alarm says when the path existed, which is when the information leaked.
- **Attackers land in a shadow world.** Every path they call works, the real one included, but the data is fake. Everyone else still gets the real service.
- **Marked keys follow them.** The fake data includes a fake API key made for that attacker. It is recognized within seconds from any IP address.
- **Bring your own LLM.** Any OpenAI-compatible API, such as Groq, can assess alarms and write the fake data. The maze itself runs on rules, so tricking the model can at most change some text in an e-mail.

**Status:** a prototype, tested end to end in a real AWS account. It is a layer on top of ordinary security, not a replacement for it. MIT licensed.

The rest of this page explains the concept in depth: the problem, the rules of the maze, the architecture, the limits, and how it compares with existing tools.

---

## Contents

1. [The problem](#1-the-problem)
2. [The idea](#2-the-idea)
3. [The three rules of the maze](#3-the-three-rules-of-the-maze)
4. [How it works](#4-how-it-works)
5. [Architecture on AWS](#5-architecture-on-aws)
6. [Two journeys through the maze](#6-two-journeys-through-the-maze)
7. [What Cloud Maze does not protect against](#7-what-cloud-maze-does-not-protect-against)
8. [Who it is for](#8-who-it-is-for)
9. [What already exists](#9-what-already-exists)
10. [How to tell it works](#10-how-to-tell-it-works)
11. [Risks and open questions](#11-risks-and-open-questions)
12. [Roadmap](#12-roadmap)
13. [Glossary](#13-glossary)

---

## 1. The problem

**Infrastructure stands still, and attackers have plenty of time.**

Almost every attack starts with reconnaissance. The attacker scans, enumerates and maps which addresses respond, which paths exist, which versions are running and which keys have leaked in old code repositories. MITRE ATT&CK has a tactic of its own for this: *Reconnaissance* (TA0043).

Reconnaissance pays off because the target stands still. An address that was open in March is usually still open in September. An API key that leaked a year ago often still works. The attacker can map at leisure, wait for a new vulnerability and strike when it suits them.

The usual defenses make each door stronger: authentication, firewalls and patching. That is necessary, but every door stays in the same place. Cloud Maze attacks the assumption itself: that the map is correct.

## 2. The idea

Picture a maze whose walls keep moving.

- **For whoever has the map**, it makes no difference. The map updates as fast as the maze does, and there is always an open path to the goal.
- **For whoever drew their own map yesterday**, it is a new maze. The corridors lead the wrong way and the doors are gone.
- **The dead ends are tripwires.** An authorized client never walks into a dead end, because the map does not show them. Anyone who does reveals that they are navigating by an old or stolen map.

On AWS, the walls are things that can already be changed through an API in seconds: paths in API Gateway, DNS names in Route 53, rules in security groups and WAF, and keys in Secrets Manager. What is missing is an engine that changes them in a coordinated, safe way, and a map that keeps authorized clients up to date. That is what Cloud Maze is.

## 3. The three rules of the maze

The concept rests on three rules that must always hold.

**Rule 1: There is always a path for the authorized.**
No change may leave an authorized client without a way in. So Cloud Maze never swaps a wall outright. The new path opens first, the map is updated next, and the old path closes only after an overlap period. During the overlap, both paths work.

**Rule 2: Every map has a best-before date.**
Everything an attacker can observe from the outside, such as paths, hostnames, ports and keys, has a limited lifetime. Once it has passed, the information is worthless. This is the map's *half-life*, and it is the most important measure in the whole system.

**Rule 3: Whoever follows an old map gives themselves away.**
A request to a path that is already closed cannot come from a working authorized client, because they always have the current map. Such requests are treated as strong signals, not noise. The maze also contains deliberate decoys: paths and keys that look real but were never handed to anyone.

## 4. How it works

### The walls: what moves

Cloud Maze moves three kinds of walls, separately or together:

| Wall | What changes | Example |
| --- | --- | --- |
| **Where** | The address of the service | `api.example.com/v1/k7f2q9/orders` becomes `api.example.com/v1/m3x8a1/orders` |
| **How** | The route there | Which source addresses are let in, which region or origin answers |
| **With what** | The keys | API keys, client certificates and secrets are rotated |

How often each wall moves is set per service. An admin interface might move every fifteen minutes. A partner API with slow-moving integrations perhaps once a day.

### The map: how the authorized find their way

Authorized clients fetch a map from a dedicated map service. The map is a small, signed document that describes how to reach the service right now and for how long that holds:

```json
{
  "service": "orders-api",
  "base": "https://api.example.com/v1/m3x8a1",
  "valid_until": "2026-10-28T14:30:00Z",
  "refresh_at": "2026-10-28T14:20:00Z"
}
```

The map service requires strong identity, such as mutual TLS, AWS IAM-signed requests (SigV4) or IAM Roles Anywhere. It is not open to just anyone. A small client library handles everything: it fetches the map, caches it, fetches a new one well before it expires and refetches at once if a request fails. To the developer it looks like an ordinary API call.

### The engine: how changes are made safely

The maze engine runs each move as a controlled process in four steps:

1. **Open** the new path and wait until it responds.
2. **Publish** the new map.
3. **Wait out the overlap**, so every client has time to switch.
4. **Close** the old path and turn it into a tripwire.

If any step fails, the move is aborted and the old path stays. The maze would rather stand still for a while than lock out the authorized.

### The tripwires: how attackers are detected

Closed paths do not disappear. They are watched. Cloud Maze also plants decoys:

- **Old paths:** paths and hostnames that were once real.
- **Fake paths:** paths that look like real services but were never on any map.
- **Fake keys:** secrets placed where an attacker would look, such as configuration files and environment variables, that grant access to nothing.

Because authorized clients never touch these, there are almost no false alarms. In practice, an alarm means someone is using information they should not have, or that has leaked.

### The shadow world: the attacker gets a maze of their own

A source that hits a tripwire does not just get an empty answer. It is put in a shadow world. There, every path works, the real one included, but everything the attacker sees is fake. The attacker believes they have succeeded and spends time on data that does not exist, while every step they take shows what they are looking for. Authorized clients are not affected, because they never hit the tripwires.

### Marked keys: the attacker stays recognizable

The fake data in the shadow world includes a *marked key*: a fake API key made for that one source, presented as a key with write access. An attacker who believes they have struck gold will try it, perhaps later, from another IP address, another machine or another tool. Cloud Maze recognizes the key within seconds wherever it comes from, sends the new address into the shadow world too, and raises an alarm that ties the new address to the one that got the key. That way the attacker cannot escape the shadow world by switching IP address, and you learn when what they found has been passed on.

### An LLM for content and analysis, not for decisions

An LLM can be connected to write convincing content for the shadow world and to assess alarms in plain language. The maze itself is driven by rules. The guarantee that the authorized always have a way in should not depend on a language model, and an attacker who tries to trick the model should at most be able to influence a piece of text. Any LLM with an OpenAI-compatible API works, such as Groq.

## 5. Architecture on AWS

```mermaid
flowchart LR
    subgraph Clients
        K[Authorized client<br/>with client library]
        A[Attacker]
    end

    subgraph Edge["The edge"]
        CF[CloudFront + AWS WAF]
        R53[Route 53]
    end

    subgraph Maze["The maze"]
        APIGW[API Gateway<br/>rotating paths]
        SVC[Your service<br/>Lambda / ECS / EC2]
        LOCK[Decoys<br/>Lambda]
    end

    subgraph Engine["The maze engine"]
        SCH[EventBridge Scheduler]
        SFN[Step Functions<br/>open → publish → wait → close]
        DDB[(DynamoDB<br/>maze state)]
        SM[Secrets Manager]
    end

    subgraph Map["The map service"]
        MAP[Map API<br/>mTLS / SigV4]
        KMS[KMS<br/>signs maps]
    end

    subgraph Alarms["Alarms"]
        CW[CloudWatch]
        SH[Security Hub]
        GD[GuardDuty]
    end

    K -->|1. fetches map| MAP
    K -->|2. calls current path| CF
    A -->|old or guessed path| CF
    R53 --> CF
    CF --> APIGW --> SVC
    CF -->|closed paths| LOCK
    SCH --> SFN
    SFN --> APIGW
    SFN --> CF
    SFN --> R53
    SFN --> SM
    SFN --> DDB
    MAP --> DDB
    MAP --> KMS
    LOCK --> CW --> SH
    GD --> SH
```

### The components

| Part | AWS services | Role |
| --- | --- | --- |
| **The edge** | CloudFront, AWS WAF, Route 53 | Receives all traffic. WAF rules that the engine updates pass traffic on current paths and send everything else to the decoys. |
| **The maze** | API Gateway, Lambda, ECS or EC2 | The service itself, unchanged. Only the route to it changes. |
| **The maze engine** | EventBridge Scheduler, Step Functions, DynamoDB | Schedules moves and runs them in the four steps. DynamoDB keeps track of current and past paths. |
| **Keys** | Secrets Manager, ACM | Rotates secrets and manages certificates. Wildcard certificates in ACM let new hostnames go live immediately. |
| **The map service** | API Gateway with mTLS, IAM Roles Anywhere, KMS | Hands out signed maps to authorized clients. The KMS signature exposes a forged map. |
| **Alarms** | CloudWatch, Security Hub, GuardDuty | Collects tripwire alarms alongside AWS's own threat signals. |

### Why AWS fits

- **Everything is an API call.** Every wall in the maze can be moved programmatically in seconds, with no manual work.
- **Pay per use.** The engine and the decoys run on services such as Lambda, Step Functions and EventBridge, which are billed per request. Little runs most of the time, so the base cost is low.
- **Built-in audit.** CloudTrail logs every change the engine makes, so you can see afterwards exactly what the maze looked like at a given moment.
- **Ready-made security infrastructure.** KMS, Secrets Manager, Security Hub and GuardDuty already exist and do not need to be built.

## 6. Two journeys through the maze

### An authorized partner

1. The partner's system starts. The client library fetches the map and identifies itself with its certificate.
2. Requests go to `/v1/m3x8a1/orders`. Everything works as usual.
3. At 14:15 the engine opens a new path, `/v1/q9z4c2/orders`, and publishes a new map.
4. At 14:20 the client library fetches the new map in the background and switches paths.
5. At 14:30 the old path closes. The partner has noticed nothing.

### An attacker

1. The attacker scans and finds `/v1/m3x8a1/orders`, perhaps through a leaked log or an old line of code.
2. The attacker spends time probing the service and prepares an attack.
3. By the time the attack runs, the path has closed. The request lands in the shadow world instead of at the service.
4. The shadow world answers convincingly with fake data. At the same time an alarm goes out with the source address, the time and which old path was used.
5. Because every path is unique to a period of time, you can see *when* the attacker got their information. If the path only appeared in a particular log or system, that points to the leak.

The fifth point is a bonus that is easy to miss: the maze does not just protect, it also traces leaks back in time.

## 7. What Cloud Maze does not protect against

Being honest about the limits matters. Otherwise the concept is just hiding things and hoping for the best.

- **Attackers with a valid identity.** Whoever has stolen an authorized client's certificate can fetch the map like anyone else. Cloud Maze makes such a theft harder to exploit for long, because keys rotate too, but it does not prevent it.
- **Vulnerabilities in the service itself.** Once an attacker reaches the right path, the maze does not protect against a bug in the code. The maze shrinks the time window; it does not fix the bug.
- **The map service is a new target.** Anything that hands out maps becomes attractive to attack. It must be especially well protected and monitored.
- **Denial of service.** Moving addresses does little against someone who just wants to flood the edge with traffic. That calls for AWS Shield.

Cloud Maze should be seen as a layer *on top of* ordinary security, not a replacement for it. It makes ordinary security more effective by removing the attacker's time advantage.

## 8. Who it is for

**The best fit** is organizations with services that must be reachable from the internet, but only by a known set of authorized clients:

- **Partner and B2B APIs**, where the counterparties are known and can use a client library.
- **Admin interfaces** that for practical reasons cannot sit entirely behind a VPN.
- **Internal service-to-service traffic**, where both sides are controlled by the same organization.
- **Highly regulated industries**, such as finance, healthcare and critical infrastructure, where regulations like NIS2 and DORA require active intrusion detection.

**A poor fit** is fully public websites and APIs that anyone should be able to use without preparation. There is no map to hand out.

**Business model:** Cloud Maze can be delivered as a ready-made stack that customers install in their own AWS account, with a license fee per protected service. That suits selling through AWS Marketplace and means the customer's traffic never leaves the customer's own account, which tends to be an important selling point for security buyers.

## 9. What already exists

Cloud Maze builds on known ideas, and several of them are available as products or open-source projects. What is new is how they are combined. This overview is based on public information from October 2026; check each project's current status yourself.

### Moving target defense

| Project | Type | What it does | How Cloud Maze differs |
| --- | --- | --- | --- |
| [Hopr](https://www.businesswire.com/news/home/20230418005347/en/Hopr-to-Display-Novel-Moving-Target-Defense-Technology-at-RSA-2023) | Commercial, on AWS Marketplace | Rotates workload credentials at high frequency and protects APIs with encrypted tunnels | Rotates credentials, not the address of the API, and has no tripwires on old paths |
| [Morphisec](https://external.pi.gpi.aws.gartner.com/reviews/vendor/morphisec) | Commercial | Moving target defense for endpoints and servers: changes memory and program behavior so malware cannot find its way | Protects the machine, not the routes to cloud services |
| [ADA](https://arxiv.org/abs/2505.23805v1) | Research | Rotates AI workloads at the Kubernetes pod level | Rotates the workload, not the address clients use, and has no map or tripwires |

### Cloud deception

| Project | Type | What it does | How Cloud Maze differs |
| --- | --- | --- | --- |
| [Tracebit](https://thenextweb.com/news/tracebit-20m-series-a-cloud-deception-security) | Commercial | Decoys and canaries across AWS, Azure, Google Cloud, CI/CD and Kubernetes | Decoys stand next to the real system. In Cloud Maze the real system itself moves, and its old addresses become the decoys. |
| [Praetorian Knossos](https://portal.praetorian.com/changelog/knossos-procedurally-generated-decoy-environments-that-turn-attackers-into-intelligence) | Commercial | Procedurally generated decoy environments that turn attackers into intelligence | Closest in spirit to the shadow world, but separate from the real service. Cloud Maze sends attackers there when they use a stale path. |
| [Acalvio](https://yespress.io/acalvio-technologies), [Fidelis](https://fidelissecurity.com/threatgeek/cloud-security/using-deception-technology-in-cloud-environments/), [CounterCraft](https://www.countercraftsec.com/blog/cloud-security-through-deception/) | Commercial | Decoy resources, fake accounts and honeytokens in the cloud | Broad deception platforms. Cloud Maze is narrow: one API, a moving address and a map. |

### Canary tokens and fake AWS keys

| Project | Type | What it does | How Cloud Maze differs |
| --- | --- | --- | --- |
| [Thinkst Canarytokens](https://docs.canarytokens.org/guide/aws-keys-token) | Free hosted service, open source, and a paid version | Fake AWS keys and many other tokens that alert you when they are used | Complements Cloud Maze, see below |
| [GitGuardian ggcanary](https://blog.gitguardian.com/press-release-canary-tokens/) | Open source (Terraform) | Thousands of fake AWS keys in your own account, alerting through CloudTrail | Complements Cloud Maze, see below |
| [Atlassian SPACECRAB](https://blog.gitguardian.com/from-vulnerability-to-advantage-turn-exposed-secrets-into-your-best-allies-to-detect-intrusion/) | Open source, older | Deploys thousands of AWS honey tokens | Complements Cloud Maze, see below |

### LLM-driven honeypots

| Project | Type | What it does | How Cloud Maze differs |
| --- | --- | --- | --- |
| [Galah](https://github.com/LubyRuffy/galah) | Open source | A web honeypot where an LLM writes fake HTTP responses | Stand-alone. In Cloud Maze, attackers reach the fake world through the tripwires of a moving maze. |
| [Beelzebub](https://ramnode.com/guides/beelzebub) | Open source | An LLM-driven honeypot for SSH and HTTP | Same as above |
| [shelLM](https://ar5iv.labs.arxiv.org/html/2309.00155), [GPTHoney](https://isc.sans.edu/diary/31342) | Research and open source | Fake shells and file systems written by an LLM | Imitate a server. Cloud Maze imitates an API. |

### Other related ideas

| Idea | What it does | How Cloud Maze differs |
| --- | --- | --- |
| **Zero trust**, such as AWS Verified Access and Cloudflare Access | Checks identity on every request | The door stays put. Cloud Maze moves the door and can be combined with zero trust. |
| **Port knocking** and Single Packet Authorization | Opens a port only after a secret signal | A static secret pattern. Cloud Maze rotates everything and alarms on old patterns. |
| **Key rotation** in Secrets Manager | Replaces secrets on a schedule | Only one wall of three, with no map or tripwires |

### What is unique

None of the projects above combines these four things:

1. **The address of a real API moves**, while authorized clients follow along through a map.
2. **Every old address automatically becomes a tripwire.** No one has to plant decoys by hand.
3. **The alarm shows when the information leaked**, because each address only existed for a known period.
4. **An attacker who uses a stale address ends up in a shadow world** of fake data, while the real service stays reachable for everyone else, and gets a marked key that keeps them recognizable on any IP address.

### Working together with canary AWS keys

Cloud Maze does not try to replace canary token tools. They catch something Cloud Maze cannot see on its own: a leaked AWS key used anywhere in AWS, from any machine. The two work well together.

**1. Hand out a canary key in the shadow world.**
An attacker in the shadow world believes they have found real data. If that data includes a canary AWS key, for example in a fake configuration object, the attacker is likely to try it. The canary then fires even if the attacker has switched IP address, machine or tool, perhaps days later. That follows the attacker even when they use the key directly against AWS, which Cloud Maze's own marked keys cannot see.

**2. Plant decoy paths and canary keys together.**
Put a Cloud Maze decoy path and a canary key in the same planted file, such as a configuration file in a repository or a CI variable. Whichever the attacker tries first, you learn that the file has leaked, and two independent alarms make it hard to dismiss as a coincidence.

**3. Send both alarms to the same place.**
Use the same e-mail address for Cloud Maze and the canary tool, or route both to the same Slack channel, so related alarms end up side by side.

**Which canary tool to choose:**

| Tool | Setup | Good to know |
| --- | --- | --- |
| [Canarytokens.org](https://docs.canarytokens.org/guide/aws-keys-token) | A form in the browser, works from a phone | Free. The key is a real AWS user without permissions in Thinkst's account. Alerts can take 2 to 30 minutes, because they go through AWS's logging. |
| [ggcanary](https://blog.gitguardian.com/press-release-canary-tokens/) | Terraform from a computer | Open source, in your own AWS account, alerts through CloudTrail by e-mail or Slack. Suits many keys at once. |
| Thinkst Canary (paid) | Managed service | From the makers of Canarytokens, for organizations that want support and central management. |

A canary key has no permissions, so it is safe to hand out. Never use a real key, and never give a canary key permissions.

**Speed:** canary AWS keys alert through AWS's logging, which takes minutes. Cloud Maze's own marked keys alert within seconds, because Cloud Maze sees the request itself. Use marked keys to follow the attacker in your API, and canary AWS keys to catch use against AWS.

The first idea, a canary AWS key in the shadow world, is not built into Cloud Maze yet. It would be an optional field in the stack where you paste a key from Canarytokens.org.

## 10. How to tell it works

A security concept has to be measurable. Cloud Maze tracks four measures:

| Measure | What it tells you | Target |
| --- | --- | --- |
| **Map half-life** | How long information about the system stays useful to an attacker | As short as the service can tolerate |
| **Authorized failures** | Share of requests from authorized clients that fail because of a move | Close to zero |
| **Tripwire hits** | Number of requests to closed paths and decoys | Every hit is investigated |
| **False alarms** | Share of hits that turn out to come from authorized clients | Close to zero, otherwise the overlap is too short |

The second and fourth measures decide whether the concept holds up in practice. If authorized clients start tripping, the maze has become too aggressive.

## 11. Risks and open questions

- **Operational complexity.** More moving parts mean more ways to break. The engine must be very easy to understand and debug, and there must be an emergency mode that freezes the maze.
- **Clients that cannot be updated.** Legacy systems and slow-moving partners may struggle to use a client library. One option is a small proxy that handles the map for them.
- **Caching and DNS.** DNS answers and CDN caches can live longer than expected. The overlap must be longer than the longest cache time, and the simplest approach is to rotate paths under a fixed domain name rather than rotating domain names.
- **Logs and debugging.** When addresses change all the time, logs get harder to read. Every log line therefore needs a stable service name in addition to the current path.
- **The perception of hiding things.** Security buyers are rightly skeptical of security that relies on things being unknown. The pitch has to focus on what can be measured: a shorter window for attackers and accurate alarms.

## 12. Roadmap

**Phase 1: Minimum viable version** (built, see [`aws/`](aws/README.md))
A service behind API Gateway with a rotating path, a map service reachable only with IAM, tripwires that send alarms by e-mail, a shadow world for sources that hit them, and marked keys that keep attackers recognizable on any IP address. An optional LLM assesses alarms and writes the shadow world's content.

**Phase 2: More walls**
Rotation of keys through Secrets Manager and of allowed source addresses in WAF. Fake keys as decoys. Integration with Security Hub.

**Phase 3: Leak tracing**
Unique paths per client and time period, so a tripwire hit points to exactly where the information leaked.

**Phase 4: Product**
Packaged installation through AWS CloudFormation or CDK, an overview of the maze's state and a launch on AWS Marketplace.

## 13. Glossary

| Term | Meaning |
| --- | --- |
| **Moving target defense** | Defense based on the target changing over time, so the attacker's knowledge goes stale |
| **Reconnaissance** | The attacker's mapping of a system before the actual attack |
| **Wall** | Something in the infrastructure that Cloud Maze can move: address, route or key |
| **Map** | A signed document that tells authorized clients how to reach the service right now |
| **Overlap** | The time when both the old and the new path work, so no authorized client is locked out |
| **Tripwire** | A closed path or a decoy that raises an alarm when someone uses it |
| **Shadow world** | Where a source that hit a tripwire ends up: every path works, but all data is fake |
| **Marked key** | A fake API key handed out in the shadow world, made for one source, that gives the attacker away wherever it is used |
| **Half-life** | How long information about the system stays useful to an attacker |
| **mTLS** | Mutual TLS, where both client and server present certificates |
| **SigV4** | AWS's way of signing requests with an IAM identity |

## License

Cloud Maze is released under the [MIT License](LICENSE).
