#!/usr/bin/env python3
"""Agenten-Bench Runde 2 – 2026-10-13b.
Kontext-Integritaets-Probes (Mid-Context Needle), Latenz, Parallelitaet,
Metrics-Snapshots. Ergebnis: JSONL + Summary. Laeuft sequentiell, Rucksicht
auf c8-Pool (dieser Chat live!)."""
import json, time, uuid, urllib.request, statistics, threading, sys

KEY = None
for line in open("/home/z000g9hu/.config/litellm/.env"):
    if line.startswith("LITELLM_MASTER_KEY="):
        KEY = line.split("=", 1)[1].strip()
GW = "http://127.0.0.1:4000/v1"          # LiteLLM-Gateway
SG = "http://127.0.0.1:8001/v1"          # sglang direkt
BO = "http://127.0.0.1:8080/v1"          # llama-server direkt
HDRS = {"Content-Type": "application/json"}
if KEY:
    HDRS["Authorization"] = f"Bearer {KEY}"
OUT = open("/home/z000g9hu/vm-lab/reviews/bench-20261013.jsonl", "a", buffering=1)

WORDS = ("wolkig zeitpuffer kernelbruecke datenstrom furniertaste spule "
         "messingklammer jahresbericht windstoessisch türrahmenspur "
         "lichtbogenofen kieselgur dampfkappe ziffernblatt nordlicht").split()

def filler(n_tokens):
    """Pseudozufaelliger Text ~ n_tokens (qwen-de ~3.6 Zeichen/Token)."""
    target = int(n_tokens * 3.6)
    parts, n = [], 0
    salt = uuid.uuid4().hex[:8]  # Radix-Cache-Busting
    while n < target:
        line = salt + " " + " ".join(WORDS[(n + j * 7) % len(WORDS)] for j in range(10))
        parts.append(line)
        n += len(line) + 1
    return "\n".join(parts)[:target]

def chat(base, model, prompt, max_tokens=48, timeout=900, extra=None):
    body = {"model": model, "max_tokens": max_tokens, "temperature": 0,
            "messages": [{"role": "user", "content": prompt}]}
    if extra:
        body.update(extra)
    t0 = time.time()
    req = urllib.request.Request(base + "/chat/completions",
                                 data=json.dumps(body).encode(), headers=HDRS)
    try:
        r = json.load(urllib.request.urlopen(req, timeout=timeout))
        dt = time.time() - t0
        u = r.get("usage", {})
        return {"ok": True, "s": round(dt, 1),
                "pt": u.get("prompt_tokens", 0), "ct": u.get("completion_tokens", 0),
                "tps": round(u.get("completion_tokens", 0) / dt, 1) if dt else 0,
                "ans": r["choices"][0]["message"]["content"][:200].replace("\n", " ")}
    except Exception as e:
        return {"ok": False, "s": round(time.time() - t0, 1),
                "err": getattr(e, "code", "") or str(e)[:120]}

def needle_probe(tag, base, model, target, timeout=900):
    code = "MARKE-" + uuid.uuid4().hex[:6].upper()
    text = filler(target // 2)
    mid = text[:len(text) // 2]
    rest = text[len(text) // 2:]
    prompt = mid + f"\nVERSTECKTE-MARKE: {code}\n" + rest + \
             "\n\nFrage: Nenne NUR die VERSTECKTE-MARKE aus dem Text."
    r = chat(base, model, prompt, max_tokens=48, timeout=timeout)
    r["tag"] = tag; r["target"] = target; r["expect"] = code
    r["needle_ok"] = bool(r.get("ok")) and code in r.get("ans", "")
    if r.get("ok"):
        r["prefill_est_tps"] = round(r["pt"] / max(r["s"] - r["ct"] / max(r["tps"], 1), 1))
    OUT.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(tag, "pt=", r.get("pt"), "needle_ok=", r["needle_ok"], "s=", r.get("s"), flush=True)

def metrics():
    try:
        txt = urllib.request.urlopen("http://127.0.0.1:8001/metrics", timeout=5).read().decode()
        want = ("sglang:num_running_reqs", "sglang:num_queue_reqs",
                "sglang:prompt_tokens_total", "sglang:generation_tokens_total",
                "sglang:token_usage")
        snap = {}
        for ln in txt.splitlines():
            if not ln.startswith("#") and any(ln.startswith(w) for w in want):
                k = ln.split(" ")[0]
                snap[k] = float(ln.split(" ")[-1])
        return snap
    except Exception as e:
        return {"err": str(e)[:80]}

def gpu_sample(stop, rows):
    import subprocess
    while not stop.is_set():
        try:
            o = subprocess.check_output(["nvidia-smi",
                "--query-gpu=memory.used,utilization.gpu,power.draw",
                "--format=csv,noheader"], timeout=5).decode().strip().splitlines()
            rows.append((time.strftime("%H:%M:%S"), o))
        except Exception:
            pass
        stop.wait(4)

def main():
    m0 = metrics()
    OUT.write(json.dumps({"tag": "metrics-before", "m": m0}) + "\n")

    stop, gpu_rows = threading.Event(), []
    gp = threading.Thread(target=gpu_sample, args=(stop, gpu_rows), daemon=True)
    gp.start()

    # A) qwen Kontext-Leiter ueber sglang direkt
    for t in (4000, 48000, 200000, 420000):
        needle_probe(f"qwen-needle-{t}", SG, "pennyroyal", t, timeout=900)

    # B) Gateway-Route gegen Direktvergleich (48k, sollte ~ identisch)
    needle_probe("qwen-via-gw-48k", GW, "local-qwen-38-flash-next", 48000, timeout=900)

    # C) bonsai Kontext-Grenze (PTQ1_0, 2 Slots, n_ctx 98304)
    for t in (4000, 40000, 90000):
        needle_probe(f"bonsai-needle-{t}", BO, "bonsai-27b", t, timeout=1200)

    # D) externes Siemens deepseek (frei, grosses Kontextfenster?)
    for t in (16000, 64000):
        needle_probe(f"deepseek-ext-needle-{t}", GW, "siemens-deepseek-41-flash", t, timeout=600)

    # E) Einzel-Latenz-Baseline (10x Mini-Request)
    lats = []
    for i in range(10):
        r = chat(SG, "pennyroyal", "Sag exakt: OK", max_tokens=8, timeout=60)
        if r["ok"]:
            lats.append(r["s"])
        time.sleep(1)
    if lats:
        OUT.write(json.dumps({"tag": "qwen-lat10", "n": len(lats),
                              "min": min(lats), "median": statistics.median(lats),
                              "max": max(lats)}) + "\n")
        print("lat10", min(lats), statistics.median(lats), max(lats), flush=True)

    # F) Parallelitaet c4 Kurzburst
    import concurrent.futures as cf
    def burst(i):
        return chat(SG, "pennyroyal",
                    f"Nenne 5 deutsche Staedte die mit {chr(65+i)} beginnen, Liste.",
                    max_tokens=120, timeout=180)
    t0 = time.time()
    with cf.ThreadPoolExecutor(max_workers=4) as ex:
        rs = list(ex.map(burst, range(4)))
    wall = time.time() - t0
    oks = [r for r in rs if r["ok"]]
    tot = sum(r["ct"] for r in oks)
    OUT.write(json.dumps({"tag": "qwen-c4", "wall": round(wall, 1), "ok": len(oks),
                          "agg_tps": round(tot / wall, 1),
                          "each": [r["s"] for r in oks]}) + "\n")
    print("c4 wall", round(wall, 1), "agg_tps", round(tot / wall, 1), flush=True)

    # G) 503-Haertetest: Pool voll? (Chat belegt bereits Slots – riskant,
    #    deshalb NUR eine Serie kleiner Requests mit Code-Erfassung)
    codes = []
    def flood(i):
        try:
            chat(SG, "pennyroyal", "Sag OK", max_tokens=8, timeout=90)
            return 200
        except Exception as e:
            return getattr(e, "code", str(e)[:40])
    # bewusst UEBER die 8er-Grenze: 12 simultan (kurz! Pool leert sich schnell)
    with cf.ThreadPoolExecutor(max_workers=12) as ex:
        codes = list(ex.map(flood, range(12)))
    OUT.write(json.dumps({"tag": "flood12", "codes": [str(c) for c in codes]}) + "\n")
    print("flood12", codes, flush=True)

    stop.set()
    m1 = metrics()
    OUT.write(json.dumps({"tag": "metrics-after", "m": m1,
                          "gpu_samples": len(gpu_rows)}) + "\n")
    with open("/home/z000g9hu/vm-lab/reviews/gpu-samples.txt", "w") as gf:
        for ts, rows in gpu_rows:
            gf.write(ts + " | " + " || ".join(rows) + "\n")
    print("DONE", flush=True)

if __name__ == "__main__":
    main()
