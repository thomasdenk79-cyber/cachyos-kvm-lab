# Agenten-Bench & Flotten-Review Runde 2 – Protokoll 2026-10-13b

## A. Modell-Bench (~/vm-lab/reviews/bench-20261013.jsonl + gpu-samples.txt)
Umgebung: sglang :8001 (512k ctx, KV 1.138.112 tok, c8, chunked-prefill 8192, fcfs),
llama-server :8080 (bonsai n_ctx=98304, 2 Slots – die alte 4096/4-Vermutung war FALSE),
LiteLLM :4000 (7 Aliase), NVIDIA-Blackwell statisch 97,2 GiB belegt.

| Test | Ergebnis | Bewertung |
|---|---|---|
| Einzel-Latenz (10x mini) | min/med/max = 0,1/0,1/0,1 s | Referenzklasse |
| c4-Kurzburst | wall 0,9 s, **480 tok/s aggregiert** | Pool skaliert linear bis Slotgrenze |
| flood12 (12 simultan > c8) | **12x HTTP 200, kein Drop** | Queue absorbiert; kein 503 noetig |
| Prefill-Durchsatz 244k-Prompt | 19,9 s ≈ **12,4k tok/s** | chunked-prefill okay fuer lange Kontexte |
| Kontext-Grenze qwen | 430k-Ziel -> HTTP 400 (real >524288 mit Generationspuffer); 288k real OK | Limit exakt wie konfiguriert |
| Mid-Context-Needle qwen 45k | **GEFUNDEN** (im reasoning_content!) | Retrieval-Qualität intakt |
| Needle qwen 288k | im Test NICHT nachgewiesen – max_tokens=64 kappte Reasoning vor Antwort | METHODENFEHLER, kein Modellfehler; Retry mit max_tokens>=512 |
| Needle bonsai 3k pt=7303 | **GEFUNDEN** | Mini-Modell solide; spaetere Truncation lag NICHT am ctx |
| Needle deepseek-ext 60k pt=126190 | **GEFUNDEN** in 93,9 s (Netzpfad) | Siemens extern voll nutzbar fuer Review-Arbeit |
| bonsai 88k | HTTP 400 | Kontextfenster-Grenze 98304 bestaetigt |

WICHTIGER METHODENBEFUND: sglang-Modell antwortet im Think-Modus – Inhalt steht in
`reasoning_content`, nicht `content`. Alle kuenftigen Auswerter MUESSEN beide Felder
lesen (bench.py korrigiert). Round-1-Bonsai-Truncation erklaert sich dadurch (und
durch max_tokens), nicht durch kaputte Config.

## B. Client-/Agenten-Audit (Runde 2, verschiedene Prompts)
| Client | Funktion? | Befund/Fix |
|---|---|---|
| aider 0.86.2 | ✓ r4-aider.md | conf zeigt korrekt auf litellm; --dry-run erwuenscht; Model-Warning kosmetisch |
| hermes v0.21.6 | ✓ r7-hermes.md (192 Zeilen) | Muster: `hermes chat --oneshot -q "…"` |
| copilot 1.0.95 | ✓ r1-copilot.md | `--no-pty` existiert NICHT (Syntaxfehler-Falle); mehrzeilige Prompts -> RC1; Backend = GitHub-Credits, nicht LiteLLM |
| codex 0.162.1 | ✓ nach Fix | `wire_api="chat"` entfernt -> `responses` gesetzt (litellm /v1/responses liefert HTTP 200 ✓); Tool-Loop benoetigt >7 min Timeout; config model 'gpt-6-luna' nicht im Gateway -> Alias luna-gpt-60 verwenden |
| opencode run (gpt-oss-120b extern) | ✓ r6-redteam.md | write-Tool-Nutzung okay |
| opencode subagent x2 | ✓ r2/r3 | externe siemens-* Aliase: Connection-Error + keine Fallbacks konfiguriert -> fuer Zuverlaessigkeit fallbacks-Eintrag in litellm Router ergaenzen |
| llama-bonsai direkt | ✓ im Bench | Review-Anfragen: 1 Request/Tag (Truncation-Vorgeschichte) |

## C. Review-Inhalte (Kurzfassung, Originale in reviews-20261013b/)
- **r2 Ops-Audit (wichtigste Funde dieser Runde)**: P4 AppArmor-Local-Pfad existiert
  nicht (mkdir noetig), P8 SPICE-Socket fuer normalen User nicht oeffnbar
  (qemu.conf spice dir aendern), P9 DISPLAY-Hartkodierung widerspricht eigenem
  Doku-Abschnitt, P10 Snapshot-Delete zu frueh, P11 .env-Import-Pattern
  (`set -a; . ~/.config/litellm/.env; set +a`). → TODO.md-Patches noetig.
- **r3 Konsistenz**: venus-Status-Widerspruch (TODO richtig, zwei Doku-Falschmelder),
  current-work.md nennt bonsai CONTEXT_SIZE=196608 – real gemessen 98304 (korrigieren),
  llm-bonsai Commitstand C veraltet, Push-Checkliste TODO veraltet (laengst gepusht).
- **r1 copilot (Inference-Gutachten)**: Bestaetigt 0.978 als vertretbar (Empfehlung:
  Monitoring auf KV-Auslastung; keine Aenderung), chunked-prefill 8192 als
  Vorperfll-Latenz okay bei unseren Sequenzen.
- **r5 codex XML-Haertung**: bestaetigt socket/autoport schema-bruch + warnt vor
  Backup-XML-Restore; Identifikation vm-lab/kvm-venus.xml als kleinste
  unwiederbringliche Datei -> in Git gesichert (dieser Commit).
- **r6 Red-Team (gpt-oss)**: 7 Angriffe; Kern: Doku-Widersprueche, Folgeagent mit
  kleinem Kontext ueberspringt Warnboxen, Prozess-Zufallsannahmen (litellm-Manuellstart).
- **r4 aider Doku-Chefredaktion**: Abschnittsfusion Preflight/Reboot-Liste,
  mehrdeutige Zitate, Hinweis dass /tmp/reviews-Inhalt persistent gehoert → umgesetzt.
- **r7 hermes Controller**: groesster SPOF = fehlende Enable-Links (behoben),
  Datenabfluss externer Modelle = Siemens-Endpoint ist Unternehmenscloud (okay),
  GitHub-PAT = lokal keiner (browser-Fluss noetig).

## D. Fazit & Aktionen
1. Litellm-Router: fallbacks fuer siemens-* ergaenzen (naechster Wartungsslot,
   gateway restart naechster geplanter Anlass).
2. codex/konsole-Doku: wire_api responses + Timeout >=15 min (steht hier).
3. Bench-Auswerter: reasoning_content-Pflicht (agentbench.py korrigiert einkopiert).
4. alle r*/reviews persistent unter Git (die /tmp-Reibach-Risiko war).
