# Cloud Maze on AWS, phase 1

This version runs for real in an AWS account. You can install and test it with nothing but a phone, without typing any commands.

Everything is installed in your own account, and only you get the API address. Anyone else who wants to try it installs it in their own AWS account the same way.

## What gets built

| Part | AWS service | What it does |
| --- | --- | --- |
| The maze engine | EventBridge and Lambda (`rotator`) | Moves the service's path every two minutes. A path lives for two intervals, the second of which is the overlap. |
| The maze state | DynamoDB | Current path, previous path, closed paths and decoys |
| The service | API Gateway and Lambda (`service`) | `GET /v1/<path>/orders`. An open path returns the real orders. A closed path or a decoy is a tripwire: the source is put in the shadow world and the answer contains fake orders. Anything else returns 404. |
| The shadow world | DynamoDB and `service` | A source that hit a tripwire gets fake orders on every path, the real one included, for 30 minutes. Authorized clients notice nothing. |
| Marked keys | DynamoDB and `service` | The fake orders include a fake API key made for that source. Whoever presents it, from any IP address, is recognized within seconds, sent into the shadow world and reported if the IP address is new for that key. |
| The analyst | Lambda (`analyst`) | Sends the alarm e-mail. With an LLM connected, the e-mail includes an assessment, and the shadow world gets fake orders written by the LLM. |
| The map service | Lambda (`map`) | Returns the current path. It can only be reached with your IAM identity, never from the internet. |
| The alarms | SNS | E-mails you when a source hits a tripwire, with the time window that shows when the path leaked. One e-mail per source, not per request. |
| The control panel | API Gateway and Lambda (`panel`) | A phone-friendly web page at a secret address. Shows the current path, old paths, a decoy, the shadow world and the marked keys, all one tap away. |

## Cost and safety limits

Nothing should cost money silently. That is why these limits exist:

1. **The maze shuts itself down after 2 hours.** The engine stops moving the path, the API starts rejecting every request, and you get an e-mail about it.
2. **The API is throttled to 2 requests per second.** Even if someone found the address and hammered it, there could not be many requests.
3. **A budget alarm, which you add yourself.** It cannot be created from the template in every region. Go to **Billing and Cost Management**, choose **Budgets**, tap **Create budget** and pick the **Zero spend budget** template. Enter your e-mail and tap **Create budget**. You then get an e-mail as soon as the account costs anything at all. Budget alarms update a few times a day, so they are a safety net, not a hard stop.
4. **Deleting the stack removes everything.** Do it when you are done.
5. **Alarm e-mails are capped at 30 per hour** (`AlarmMaxPerHour`), and LLM calls at 20 per hour (`LlmMaxCallsPerHour`). An attacker with many IP addresses cannot flood your inbox or run up an LLM bill. When the alarm cap is hit you get one e-mail saying so, and further alarms that hour are only logged.

Every part is billed per use, and a test round makes only a few hundred requests, so the cost is effectively zero. Lambda and API Gateway also have free tiers. When you create a new AWS account you may be offered a free plan with starting credits, under which the account is not charged at all. Check what applies when you sign up.

## Install from a phone without typing commands

Everything is done with buttons in the AWS console. The only things you type are a stack name and your e-mail address.

### 1. Create an AWS account

Go to https://aws.amazon.com and choose to create an account. You need an e-mail address, a payment card and your phone for verification. Choose the free plan if you are asked.

### 2. Download the template to your phone

Tap and hold this link and choose **Download Linked File**:

https://github.com/mikaelcarlevigg/cloud-maze/raw/main/aws/template.yaml

The file ends up in your Downloads folder. If that does not work, download the whole repository as a ZIP from https://github.com/mikaelcarlevigg/cloud-maze/archive/refs/heads/main.zip, open it in the Files app to unpack it, and use `aws/template.yaml` from the unpacked folder.

### 3. Install with CloudFormation

1. Open https://eu-north-1.console.aws.amazon.com/cloudformation/home?region=eu-north-1#/stacks/create. It goes straight to creating a stack in the Stockholm region. To use another region, change it in the top right.
2. Choose **Upload a template file**, tap **Choose file** and pick `template.yaml` from Downloads. Tap **Next**.
3. Enter `cm` as the **Stack name** and your e-mail address under **AlarmEmail**. Make sure there is no space after the address; iPhone sometimes adds one when you pick a suggestion. Leave the rest, or fill in the LLM fields (see [Connect an LLM](#connect-an-llm)). Tap **Next**.
4. Tap **Next** again on the next page.
5. At the bottom, tick **I acknowledge that AWS CloudFormation might create IAM resources** and tap **Submit**.
6. Wait until the stack shows **CREATE_COMPLETE**. It takes 2–3 minutes. Pull down to refresh.

### 4. Confirm the alarms

Open the e-mail from AWS Notifications and tap **Confirm subscription**. Otherwise no alarms arrive.

### 5. Test in the control panel

Go to the stack's **Outputs** tab and tap the link next to **PanelUrl**. Bookmark the page if you like. The address contains the stack's unique id, so only you can find it.

The panel refreshes every 15 seconds and has five parts:

- **Authorized client:** shows the path the map gives right now. Tap it and you get the orders. Wait two minutes and see that the path has changed.
- **Old paths:** once the first path has closed, after about four minutes, it shows up here. Tap it: the answer looks real, but the orders come from customers other than Nordvind AB and are fake. You get an alarm e-mail that shows between which times the path existed, which is when it leaked.
- **Decoy:** a path that was never on any map. It behaves like an old path.
- **Shadow world:** after you tap an old path or the decoy, your IP address is listed here and the panel says so at the top. Tap the authorized path again: now it gives fake orders too. That is what an attacker experiences. After 30 minutes you are let out.
- **Marked keys:** the fake orders came with a fake API key made for your IP address. Tap **use it** next to the key: it is recognized at once. Then **turn off Wi-Fi** so your phone gets a new IP address over mobile data, and tap **use it** again. You get an alarm e-mail that says the key was handed out to one address and is now used from another, and the new address goes into the shadow world too.

Use the browser's back button to return to the panel.

### 6. Remove everything

In CloudFormation, select the stack `cm` and tap **Delete**. Type the stack name to confirm. Everything that was installed is removed.

You do not have to delete it right away: after 2 hours the maze shuts itself down, and what is left sits idle and costs practically nothing. Delete it when you are done, or when you want a new test round, since the maze does not restart on its own.

## Install with commands in CloudShell

If you prefer commands, you can install from AWS CloudShell, the terminal in the AWS console. That also gives you an authorized client and attacker scripts that run in the terminal.

### Open CloudShell

1. Sign in at https://console.aws.amazon.com.
2. Pick a region in the top right, for example **Europe (Stockholm)**.
3. Search for **CloudShell** in the search bar at the top and open it. The first start takes a minute.

Pasting into CloudShell often does not work on a phone. That is why you only have to type two short lines. The rest is done with numbers in a menu.

### Get the code and start the menu

Type these two lines and press Enter after each:

```bash
git clone https://github.com/mikaelcarlevigg/cloud-maze
cloud-maze/cm
```

The menu looks like this:

```
========== Cloud Maze ==========
Account: 123456789012, region eu-north-1
Status: not installed

  1  Install
  2  Run the authorized client (6 min)
  3  Attacker: steal the current path
  4  Attacker: attack with the stolen path
  5  Attacker: try a decoy
  6  Attacker: guess a path
  7  Remove everything
  0  Exit the menu
```

If you come back later, or CloudShell has restarted, just type `cloud-maze/cm` again.

### Test from the menu

1. **Choose 1** and enter your e-mail address. Installation takes a few minutes.
2. **Open the e-mail from AWS Notifications and tap *Confirm subscription*.** Otherwise no alarms arrive.
3. **Choose 2.** The authorized client fetches the map with your IAM identity and calls the service every ten seconds for six minutes. You see it switch paths every two minutes without a single request failing.
4. **Choose 3.** You steal the path that is current right now, as if it had leaked in a log. It works, and you get the orders.
5. **Wait 4–5 minutes.** The menu shows *CLOSED* once the stolen path has closed.
6. **Choose 4.** The answer looks normal, but the orders are fake. Check your e-mail: there is an alarm that tells you which path was used, where the request came from, and between which times the path existed. That is when the leak happened.
7. **Choose 5 and 6.** A decoy alarms the same way. A guessed path just returns 404 and no alarm.
8. **Choose 7** when you are done. It removes everything that was installed.

CloudShell has a single IP address, so after step 4 the authorized client in the same CloudShell is in the shadow world too. The client points out when it gets fake orders.

You can also open the stolen address in your phone's browser. It is printed when you choose 3.

If you prefer commands to the menu, the scripts `deploy.sh`, `client.sh`, `attacker.sh` and `destroy.sh` are in the same folder.

## Connect an LLM

Cloud Maze works without an LLM. If you connect one, it does two things:

1. **Assesses the alarm.** The alarm e-mail gets a short analysis: what happened, how serious it is and what you should do.
2. **Writes the shadow world.** It creates convincing fake orders that attackers in the shadow world get to see.

You can use any provider with an OpenAI-compatible API, which most have. You fill in three fields when you create the stack:

| Field | Groq | Other provider |
| --- | --- | --- |
| **LlmBaseUrl** | `https://api.groq.com/openai/v1` | The provider's OpenAI-compatible address, for example `https://api.openai.com/v1` or `https://api.mistral.ai/v1` |
| **LlmModel** | `llama-3.3-70b-versatile` | A model name from the provider's list |
| **LlmApiKey** | Your key from Groq | Your key from the provider |

If you leave the fields empty, everything runs without an LLM and the e-mails contain only the facts.

If you install with `deploy.sh` in CloudShell, put the address and model in front of the command. The script then asks for the key:

```bash
LLM_BASE_URL=https://api.groq.com/openai/v1 LLM_MODEL=llama-3.3-70b-versatile ./deploy.sh you@example.com
```

### Getting a key from Groq

1. Sign in at https://console.groq.com.
2. Choose **API Keys** and **Create API Key**.
3. Copy the key and paste it into the **LlmApiKey** field when you create the stack. Pasting into forms in the browser works fine, unlike in CloudShell.

Also check that the model name is in Groq's model list, since the selection changes.

### Security and cost

- **The LLM decides nothing.** It has no tools and cannot open paths, turn off alarms or release anyone from the shadow world. The facts in the e-mail, such as path, IP address and time window, always come from the code. The LLM's text is added below them.
- **Attacker data is only data.** Things the attacker controls, such as the user agent, are sent to the LLM with a clear instruction that they are data, not instructions. Even if someone manages to trick the model, they can only influence the text of the e-mail.
- **The fake orders are checked.** Only fields with the right type and reasonable values are kept. Everything else is discarded.
- **A cap on calls.** At most 20 LLM calls per hour (`LlmMaxCallsPerHour`). The LLM is only called when a new source hits a tripwire, not on every request.
- **If the LLM does not answer**, the e-mail goes out anyway, with a line about the error.
- **The key** is hidden in the CloudFormation form but stored as an environment variable on the `analyst` function. Anyone with administrator access to your account can see it. In production the key belongs in AWS Secrets Manager. That costs a small amount every month, which is why it is not the default here.

## Your own credentials

Everything is installed in the AWS account you are signed in to. How you sign in depends on where you run it:

- **The CloudFormation console** (the button-based install above): you are signed in through the browser. No keys are needed.
- **AWS CloudShell:** you are already signed in as the user you used for the console. No keys are needed.
- **Your own computer:** install the [AWS CLI](https://aws.amazon.com/cli/). If you have already run `aws configure`, those credentials are used. Otherwise the scripts ask for your keys when you start them.

Keys you type when the scripts ask are only used while the script runs. They are never saved to disk or to the repository. The secret is not shown as you type.

Before anything is installed, the script shows which account and region it will use, and you must type `y` to continue. If no region is set, `eu-north-1` (Stockholm) is suggested. The client and attacker scripts also check that you are signed in to the same account the maze was installed in.

### Creating keys

1. Sign in to the AWS console and open **IAM**.
2. Choose **Users** and **Create user**. Do not use the root user's keys.
3. Give the user permissions. For a test, **AdministratorAccess** is simplest, since the stack creates roles, functions, a table and an API.
4. Open the user, go to **Security credentials** and choose **Create access key** with the use case **Command Line Interface (CLI)**.
5. Save the **Access key ID** and **Secret access key**. The secret is shown only once.

Delete the key, or the whole user, when you are done testing. Never put keys in code, in the repository or in chats.

If you have temporary keys, for example from AWS IAM Identity Center, also fill in the **session token** when the script asks.

## Tests

The Lambda functions can be tested on your own computer, against fake AWS services and a fake LLM. No AWS account and no extra packages are needed, just Python 3.9 or later:

```bash
python3 -m unittest discover -s aws/tests -v
```

The tests read the code straight from `template.yaml`, so they always test what gets installed.

## Settings

```bash
./deploy.sh you@example.com 5     # move the path every 5 minutes instead of every 2
```

How long the maze runs (`RunHours`) and how long a source stays in the shadow world (`ShadowMinutes`) are chosen when you create the stack, or in `template.yaml`. The maze does not restart on its own after it has shut down. Delete the stack and create it again.

## Security review

This section lists what an attacker could exploit in this prototype, found by reviewing it as an attacker would. The first four were fixed; the rest are limits of the prototype that a real deployment has to solve.

**Fixed**

- **Inbox flooding.** An attacker with many IP addresses could trigger one alarm e-mail per address. Alarm e-mails are now capped per hour.
- **Phishing links through the LLM.** An attacker can put text in the user agent that steers the LLM, for example to add a link to a fake login page in the e-mail to you. Links are now removed from the LLM's text. The facts above it always come from the code.
- **A table that only grows.** Marked keys were kept forever. They now expire after 30 days.
- **An incomplete panel.** With many entries, the panel only read the first page of the table. It now follows up to ten pages.

**Known limits**

- **The throttle can be used against you.** The limit of 2 requests per second applies to the whole API, not per source. That protects your bill, but an attacker who sends more than that can make authorized clients get errors. A real deployment needs per-IP rate limits, for example a rate-based rule in AWS WAF, which has a fixed monthly cost.
- **Shared IP addresses.** The shadow world recognizes sources by IP address. An authorized client behind the same address as an attacker, such as in an office, a VPN or a mobile network that shares addresses, also gets fake data, without noticing. A real deployment should have authorized clients sign their requests to the service and only send unsigned requests into the shadow world.
- **The deception can be spotted.** An attacker who saw the real orders before the path closed will notice that the customers change. The `meta` field with the marked key only appears in fake answers, and unknown paths and unknown routes answer with slightly different error messages. A careful attacker can use such differences to tell the shadow world from the real service.
- **The alarm cap is also a blind spot.** An attacker who first triggers many alarms can hide a later, targeted one in the same hour. It is still in the logs, but not in your inbox.
- **The panel address is a key.** Anyone with the panel address can see the current path, which is the map. Do not share it or show it in screenshots.
- **The service has no login of its own,** and the LLM key is stored as an environment variable. Both are described elsewhere in this guide.

## Differences from the concept

Phase 1 shows the core: the path moves with overlap, the authorized find their way through the map, and old paths and decoys raise alarms and lead into the shadow world. This is still missing:

- **The path check happens in Lambda.** In the concept, CloudFront and WAF stop old paths at the edge.
- **The map is not signed.** IAM protects it, but KMS signing is not included yet.
- **Only the address moves.** Keys and allowed source addresses do not rotate.
- **The service has no login of its own.** In reality Cloud Maze is a layer on top of ordinary authentication.
- **Alarms go out by e-mail.** A real version would collect them in Security Hub.
- **The shadow world recognizes sources by IP address.** Several users behind the same IP address, such as in an office or in CloudShell, end up there together. Marked keys follow an attacker who switches address, but only if they use the key.
- **Marked keys are accepted in the address as `?api_key=`** so they can be tested with a tap. A real API would only accept keys in a header.
