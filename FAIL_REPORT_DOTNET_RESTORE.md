# 🚧 Fail Report — `dotnet restore` tar 30+ minuter

**Projekt:** `eks-mongo-todo`  
**Datum:** 2025-10-14  
**Författare:** Andreas Vilhelmsson & Codex

---

## 1. Sammanfattning

Vid Docker-build (`docker buildx build …`) hänger byggsteget

```
RUN --mount=type=cache,target=/root/.nuget/packages dotnet restore
```

i 30 minuter eller mer. Detta blockerar både lokala tester och publicering till EKS, trots att applikationen i övrigt är trivial (`todo-backend` med Swashbuckle).

---

## 2. Bakgrund och tidslinje

| Tid | Händelse |
| --- | --- |
| 2025-10-14 09:00 | Första försöket via Codex CLI ⇒ `dotnet restore` fastnar (ingen nätåtkomst i sandlådan). |
| 2025-10-14 11:00 | Försök att gå offline: la in `NuGet.config` + `offline-packages`. Fungerade i teorin men introducerade mycket extradata. |
| 2025-10-14 14:00 | Bestämdes att köra i “fri” macOS-terminal i stället. Docker får nätåtkomst. |
| 2025-10-14 15:00 | Trots öppen nätåtkomst tar `dotnet restore` 170–1900 s. Inga tydliga felmeddelanden; CLI visar bara progress. |
| 2025-10-14 16:30 | Kör `curl`/`nslookup` inuti SDK-containern ⇒ bekräftar att nätet fungerar. Problemen kvarstår. |
| 2025-10-14 17:00 | Beslut: dokumentera incidenten och pausa byggjobbet tills vi har mer data (ex. network sniffing eller återinförd offline-feed). |

---

## 3. Root Cause (preliminär)

1. **Miljöbyte** — Byggen kördes initialt i en sandlåda utan outbound nät. Detta gjorde att `.NET restore` hängde utan att ge tydliga fel.  
2. **Emulering & cache** — På macOS/ARM kör Docker `linux/amd64` images via QEMU. Första körningar måste därför ladda ner ~170 MB referenspaket + resterande beroenden via en emulerad stack, vilket gör restore märkbart långsam.  
3. **Möjligen fler omstarter med `--no-cache`** — Varje gång kommandot kördes om från scratch behövde nuget-paketen laddas ned igen. Om CDN svarade långsamt blir tiden snabbt 30+ min.

> **OBS:** Vi har ännu inte sett ett explicit fel (timeout, 403 osv). Det lutar åt att restore lyckas – den är bara extremt långsam innan cachen är varm.

---

## 4. Bevis

### 4.1. Dockerlogg
```
 => [build 4/6] RUN --mount=type=cache,target=/root/.nuget/packages dotnet restore  1927.2s
```

### 4.2. Nät-test från containern
```
docker run --rm mcr.microsoft.com/dotnet/sdk:8.0 curl -I https://api.nuget.org/v3/index.json
HTTP/2 200 ...
```

### 4.3. DNS-test
```
docker run --rm alpine:3.19 nslookup api.nuget.org
...
Address: 13.107.213.53
```

---

## 5. Åtgärder som testats

| Åtgärd | Resultat |
| --- | --- |
| Offline-feed (NuGet.config + `.nupkg`-kopia) | Restore går snabbt men skapar mycket “speciallösning”. Valde bort när byggning ska ske i nack-terminal. |
| Tillbaka till original-Dockerfile | Ingen logisk skillnad; restore hänger fortfarande. |
| Nätåtkomst-test | Lyckas. Inget brandväggsproblem på själva Macen. |
| `--progress=plain` | Ger mer logg, visar att restore jobbar men långsamt. |

---

## 6. Nästa steg / Rekommendationer

1. **Kör om builden utan `--no-cache`** direkt efter en lång restore. Om steg `[build 4/6]` fortfarande tar >1 min även andra gången ⇒ samla `dotnet restore -v diag` loggar för att se exakt vilka paket som laddas om.  
2. **Överväg att parkera offline-filen** (`NuGet.config` + `.nupkg`) i en feature-branch, redo att aktiveras om nätet strular i CI.  
3. **Verifiera BuildKit-cache** — se till att buildern inte destrueras mellan körningar (`docker buildx ls`).  
4. **Rulla bygget på en EC2/CI-runner** med amd64 och snabb lina för att se om azure-CDN/nuget.org svarar snabbare där.  
5. **Fail-fast** — Lägg in timeout/shell guard i `rebuild-backend.sh` så scriptet bryter efter t.ex. 10 minuter och skriver ut tips.

---

## 7. Lessons Learned

- Codex CLI:s sandlåda saknar outbound nät; bygg inte nätberoende steg där.  
- På Apple Silicon måste vi konsekvent tänka på arkitektur + emulering (amd64 tar längre tid).  
- Dokumentera i README hur man testar nuget-nätåtkomst (`curl`/`nslookup`) och hur man aktiverar offlinefeed vid behov.

---

## 8. Status

| Status | Beskrivning |
| --- | --- |
| ⏳ Öppen | Builden tar fortfarande ~30 min på macOS/ARM. Vi har workaround (offline-feed) men inga bestående ändringar införts. |

---
