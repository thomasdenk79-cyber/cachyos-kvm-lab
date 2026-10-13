**Leistungsgutachten pennyroyal (sglang, RTX PRO 6000 Blackwell, 96 GB)**

**1. mem-fraction-static 0.978**
- Nutzen: Der KV-Pool wächst nur marginal. Von 0.95 auf 0.978 sind das ca. 2,8 % von 96 GB, also etwa 2,7 GB. Das entspricht grob 30–60k Tokens zusätzlich, je nach KV-Bytes pro Token.
- Risiko: Hoch. Bei 0.978 bleiben nur ca. 2 GB für alles außerhalb des statischen Pools:
  - CUDA-Graph-Buffer
  - Aktivierungen beim Prefill (8192-Chunk)
  - NCCL-/cuBLAS-Workspaces
  - Fragmentierung
- OOM-Spitzen sind realistisch bei:
  - Prefill-Chunks mit großem Logits-/MoE-Zwischenspeicher
  - gleichzeitigem Sampling mit großen Batches
  - Speculative- oder Graph-Capture-Pfaden
- Bewertung: Der Gewinn von etwa 3 % Kapazität steht in keinem Verhältnis zum OOM-Risiko. Ich würde 0.93–0.95 testen. Ein OOM bei 500k-Kontext kostet mehr als 50k Tokens Pool.

**2. chunked_prefill 8192 bei 200k+ Prompts**
- 200k Tokens bedeuten ca. 25 Chunks. Jeder Chunk attendiert über den wachsenden Cache, daher wird die Attention quadratisch teurer. Der Overhead pro Chunk (Scheduling, Kernel-Launches) fällt bei kleinen Chunks relativ stärker ins Gewicht.
- Für den Durchsatz einer einzelnen Anfrage ist 8192 eher zu klein. 16384 oder 32768 verkürzen TTFT bei langen Prompts oft um 10–25 %.
- Der Nachteil größerer Chunks ist höherer Aktivierungsspeicher und längere Decode-Stalls für parallele Sessions. Das passt schlecht zu 0.978.
- Test: `--chunked-prefill-size 16384` und `32768`, gleichzeitig mit mem-fraction 0.94. Gemessen werden TTFT für 200k und die p99-Inter-Token-Latenz parallel laufender Decodes.

**3. KV-Engpass bei Sessions mit 60k Kontext**
- Pool: 1.138.112 Tokens ÷ 60.000 ≈ **18,97, also 18 Sessions** passen vollständig.
- Ab der 19. aktiven Session mit voller Länge ist der Pool voll. Das führt zu Eviction im Radix-Cache oder zu Retraction/Preemption.
- Mit max_running_requests=8 sind nur 8 × 60k = 480k Tokens gleichzeitig aktiv, der Pool reicht also. Die übrigen ca. 650k Tokens dienen als Prefix-Cache für wartende Sessions.
- Praktisch wird der Pool also nicht durch c8 begrenzt, sondern durch die Zahl **gehaltener** Sessions (ca. 18).
- Kommen Sessions mit 200k+ dazu, sinkt der Wert deutlich. Vier Sessions mit 200k belegen bereits 800k Tokens.

**4. Nächste Messungen (max. 3)**

a) Tatsächliche Speicherreserve und Pool-Zustand:
```
curl -s localhost:30000/get_server_info | jq '.internal_states, .max_total_num_tokens'
nvidia-smi --query-gpu=memory.used,memory.total --format=csv
```
Der Wert von nvidia-smi ist unter Last (8 parallele Prefills) zu wiederholen. Gefragt ist der freie Rest in MB.

b) TTFT für einen langen Prompt (ca. 200k):
```
curl -s localhost:30000/v1/chat/completions -H 'Content-Type: application/json' -d "$(jq -n --rawfile p prompt200k.txt '{model:"pennyroyal",messages:[{role:"user",content:$p}],max_tokens:16,stream:false}')" -w '\nTTFT/total: %{time_total}s\n'
```
Wiederholen mit variiertem Chunk-Size nach Neustart.

c) Decode-Stall während eines Prefills:
```
curl -sN localhost:30000/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"pennyroyal","messages":[{"role":"user","content":"Zähle bis 500."}],"max_tokens":500,"stream":true}' -w '\n%{time_starttransfer}\n'
```
Das läuft parallel zu (b). Die Lücken zwischen den Tokens im Stream sind die Stalls.

Hinweis: Port und Modellname sind angenommen. Das Gutachten stützt sich auf die genannten Parameter, nicht auf eigene Messungen.

