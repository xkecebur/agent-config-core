---
name: blue-team-detection
description: Defensive security — detection engineering (Sigma rules, alert quality, detection-as-code), logging that is actually useful during an investigation, incident triage and timelines, and translating known attack techniques into detections. Use when designing alerts or detection rules, deciding what an application should log, investigating suspicious activity, writing an incident post-mortem, or answering "how would we detect this".
alwaysApply: false
---

# Blue Team — Detection & Response

Detection is written by people who understand how the attack works. Every offensive
technique is a candidate detection rule — this module is about making that translation
deliberate.

## Logging that survives an investigation

Most applications log plenty and still cannot answer "who did what, when". The events
that matter:

| Event | Minimum fields |
|---|---|
| Login success/failure | timestamp, user id, source IP, user agent, outcome, failure reason |
| Authorization **denied** | user id, target resource, missing permission |
| Privilege or role change | actor, target, old value → new value |
| Password / email / MFA change | actor, method, whether re-authentication was required |
| Sensitive data access | user id, resource id, record count |
| Admin API call | actor, endpoint, parameters (excluding secrets) |

Rules:

- **Structured logs** (JSON), not free-form strings — you cannot correlate what you have to regex
- Include a **trace/correlation id** so one request can be followed across services
- **Never** log passwords, tokens, session ids, or raw PII — doing so creates the very
  exposure you are defending against
- Failed authorization events are more valuable than successful ones. Enumeration and
  broken object-level authorization show up there first

## Detection engineering

A good detection targets behaviour the attacker cannot easily avoid. A weak detection
targets an indicator they can change in seconds.

Pyramid of pain, easiest to hardest for an attacker to change:
hash → IP → domain → artifact → **tool** → **TTP**. Aim at the last two.

```yaml
title: Password spray - many distinct users failing from one source
logsource: { product: application, service: auth }
detection:
  failed:
    event: authentication_failure
  timeframe: 15m
  condition: failed | count(distinct user_id) by source_ip > 20
level: high
```

Mapping offensive techniques to defensive signals:

| Technique | Detection signal |
|---|---|
| Password spray | many distinct `user_id` failures from one IP/ASN in a short window |
| Credential stuffing | high failure ratio + uniform user agent + distributed source IPs |
| IDOR / enumeration | one user touching many sequential `resource_id`s; spike in 403s |
| SQL injection | database errors on an endpoint that is normally clean; anomalous query duration |
| Subdomain reconnaissance | NXDOMAIN spike, requests for hosts that were never published |
| Web shell upload | new file in an upload directory followed by the first request to that path |
| SSRF | egress from a service toward internal ranges or `169.254.169.254` |
| Data exfiltration | response volume far above that user's baseline |

## Alert quality

- Every alert needs a **runbook**: what it means, how to verify, first action, how to close
- An alert nobody acts on is noise, and noise is why real alerts get missed
- Measure: true positive rate, time to triage, and alerts closed without investigation
  (a strong signal the rule is bad)
- **Detection as code**: rules live in git, get reviewed like code, and have tests built
  from sample logs

## Incident triage

1. **Scope** — what is affected, since when, is it ongoing?
2. **Contain** — stop the spread (revoke sessions and tokens, isolate hosts, block the path)
   before attempting eradication
3. **Preserve** — collect evidence before changing anything (logs, memory, disk images);
   hasty cleanup destroys the forensic trail
4. **Eradicate** — remove attacker access including persistence (new keys, accounts,
   cron entries, webhooks)
5. **Recover** — restore from a known-good state and watch for recurrence
6. **Learn** — blameless post-mortem

Timelines use **UTC** and cite the source of every entry.

## Post-mortem questions

- How was this detected — an alert, or a human noticing? If not an alert, which detection is missing?
- How long from compromise to detection, and from detection to containment?
- Which control should have stopped this and did not?
- What new detection comes out of this incident?

## Related modules

- Application and container hardening → `security-audit`
- Pipeline hardening → `devops-pipeline`
