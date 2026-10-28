# Cloud Maze, local simulation

Try Cloud Maze on your own computer. You need no AWS account and no extra packages, just Python 3.9 or later.

The simulation implements the same logic as the concept in the [main README](../README.md): a service whose path moves, a map service for the authorized, and tripwires that raise an alarm when someone uses an old path.

## Only have a phone?

Open `web.html` in a browser. It runs the same logic right in the page, and you play the attacker with buttons.

## Getting started

Get the repository and go to the folder:

```bash
git clone https://github.com/mikaelcarlevigg/cloud-maze.git
cd cloud-maze/sim
```

### 1. See the whole thing in 20 seconds

```bash
python3 demo.py
```

The demo runs an authorized client and an attacker against the same maze and narrates what happens:

```
    0.0 s  ENGINE     the first path is 896241
    1.0 s  ATTACKER   finds path 896241 in a leaked log and saves it
    4.0 s  ENGINE     opens new path ae102e and publishes the map
    4.6 s  CLIENT     uses path ae102e from the map, got the orders
    5.5 s  ENGINE     closes 896241, it is now a tripwire
    8.8 s  ALARM      old path used: 896241
    8.8 s  TRACE      path 896241 only existed 0.0 s to 5.5 s, so that is when it leaked
    8.8 s  ATTACKER   attacks through 896241: answer 200, {"orders": []}
    ...
Result
  Authorized client: 80 of 80 requests succeeded, 0 failed, switched paths 4 times
  Alarms:            3, of which 0 false alarms
  Attacker:          got 0 orders through old paths and decoys
```

Notice three things:

- **The client notices nothing.** It switches paths every time the map updates, and no request fails.
- **The attacker is fooled.** The old path answers as usual but returns no orders, so the attacker does not know it has been detected.
- **The leak can be traced.** The alarm shows exactly when the stolen path existed, which points to when the information leaked.

You can change the pace, for example `python3 demo.py --interval 6 --overlap 2 --duration 30`.

The local simulation answers stale paths with an empty list. The AWS version goes one step further and sends the attacker into a shadow world of fake orders.

### 2. Be the attacker yourself

Start the server in one terminal window:

```bash
python3 server.py
```

The server prints the current path and a command to start an authorized client. Run that command in a second window. The client calls the service every second and shows when it switches paths.

Then play the attacker in a third window:

1. Copy the path the server shows right now and run `curl` against it. You get the orders.
2. Wait until the server prints `CLOSED` for that path. It takes about 25 seconds with the default settings.
3. Run the same `curl` again. You get an empty answer, and the server prints `ALARM`.
4. Also try one of the paths listed under `Decoys`, or `curl http://127.0.0.1:8080/map` without keys.

The client in the second window keeps working the whole time.

### 3. Run the tests

```bash
python3 -m unittest -v
```

The tests check the maze's three rules: that there is always an open path, that an authorized client never fails when the path moves, and that old paths and decoys raise alarms.

## What each file corresponds to on AWS

| File | What it does | On AWS |
| --- | --- | --- |
| `maze.py`, class `Maze` | Keeps track of open, closed and fake paths | DynamoDB |
| `maze.py`, class `Engine` | Moves the path in four steps: open, publish, wait, close | EventBridge Scheduler and Step Functions |
| `server.py`, `/v1/<path>/orders` | The service behind the rotating path | CloudFront, AWS WAF and API Gateway |
| `server.py`, `/map` | The map service, for the authorized only | API Gateway with mTLS or SigV4 |
| `server.py`, map signing | Exposes a forged map | AWS KMS |
| `server.py`, the alarms | Tripwires and decoys | Lambda, CloudWatch and Security Hub |
| `client.py` | Fetches the map, checks the signature, switches paths in time | The client library |

## Simplifications

The simulation shows the idea, but it is not safe to use for real:

- Clients and map signing use shared secret keys (HMAC). On AWS, clients would identify themselves with certificates or IAM, and KMS would sign the map with an asymmetric key.
- The service has no login of its own. In reality Cloud Maze is a layer on top of ordinary authentication, not a replacement for it.
- Everything runs in one process on one computer, and the maze state is lost when the server stops.
- Only the address moves. Keys and allowed source addresses do not rotate yet.
