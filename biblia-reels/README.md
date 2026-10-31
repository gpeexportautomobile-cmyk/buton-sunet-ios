# Biblia Reels

Aplicație iOS gratuită: o rolă pe ecran, un verset, în ordine. Prototipul conține **Geneza 1–3** din **Cornilescu 1924** (ortografie veche). Numele și semnul sunt ale noastre.

IPA-ul rămâne mic. În el stau textul, personajele și un semn de 64×64 plus un sunet scurt de rezervă. Imaginile și narațiunea vin dintr-un `manifest.json` de la o adresă pe care o pui tu. La fiecare deschidere aplicația cere manifestul din nou: versetele și personajele noi apar fără o versiune nouă a aplicației. Unde încă nu există poză sau voce, vezi un desen făcut pe telefon și auzi vocea română a sistemului, cu evidențiere cuvânt cu cuvânt.

## Instalează IPA-ul

1. Deschide workflow-ul **Build Biblia Reels** din acest depozit (rulează la push pe `biblia-reels/` și la cerere).
2. Descarcă artifactul **BibliaReels-ipa**.
3. Instalează-l cu același program cu care instalezi celelalte IPA din acest depozit. Semnătura este ad-hoc, fără cont Apple plătit.
4. Telefonul trebuie să aibă **iOS 15** sau mai nou.

La primul pornire vezi cele 80 de versete, butoanele de apreciere, comentariu (rămâne pe telefon), salvare și distribuire, profilele personajelor, căutarea, reflecțiile și mesajele.

## Fabrica de imagini și voce (GPU gratuit)

Tot ce ține de poză, bio și voce se face într-un notebook, nu în aplicație. Pașii sunt reluabili: ce este deja scris pe disc se sare.

1. Deschide notebook-ul în Colab (GPU T4, gratuit):

   `https://colab.research.google.com/github/gpeexportautomobile-cmyk/buton-sunet-ios/blob/main/biblia-reels/factory/genereaza.ipynb`

   Pe Kaggle: notebook nou, Settings → Accelerator → GPU, apoi rulează aceleași celule.

2. În Colab: Runtime → Change runtime type → T4. Rulează celulele de sus în jos.
3. Până când fișierele sunt pe `main`, în prima celulă lasă `FALLBACK = "cursor/biblia-reels-ff92"` (este deja acolo). După merge, `BRANCH = "main"` este de ajuns.
4. Pentru o probă de un verset, în celula de rulare schimbă `--limit 0` în `--limit 1`. Pentru toată Geneza 1–3 lasă `0`.
5. Dacă sesiunea gratuită se oprește, rulează notebook-ul din nou. Nu o ia de la capăt.
6. Descarcă folderul `biblia-reels/factory/output`. Înăuntru trebuie să fie `manifest.json`, `images/`, `audio/` și, când sunt gata, `avatars/`.

Dacă Hugging Face cere acceptarea condițiilor pentru FLUX.1-schnell, fă un cont gratuit, acceptă și pune tokenul în secretul Colab `HF_TOKEN`.

Ce face fabrica, în ordine:

- Qwen2.5-7B-Instruct (4-bit) scrie un stil comun al personajelor, un prompt de imagine pentru fiecare verset și o bio în română.
- FLUX.1-schnell (Apache-2.0) face poze 9:16 și portretele.
- Piper, vocea `ro_RO-mihai` (setul de antrenare este CC0), citește versetul. ffmpeg îl pune în AAC (`.m4a`), ca să îl poată reda iOS-ul. Timpii cuvintelor sunt estimați pe zona în care se aude vocea.

## Unde pui fișierele

Adresa trebuie să servească `manifest.json` la rădăcină și căile din el (`images/gen.1.1.webp`, `audio/gen.1.1.m4a`).

**GitHub Pages**

```bash
git clone https://github.com/gpeexportautomobile-cmyk/buton-sunet-ios.git pagini
cd pagini
git checkout --orphan gh-pages
git rm -rf .
cp -R /calea/către/output/. .
git add manifest.json images audio avatars
git commit -m "Media Biblia Reels"
git push -u origin gh-pages
```

Apoi pe GitHub: Settings → Pages → Branch `gh-pages`, folder `/ (root)` → Save. După un minut adresa este:

`https://gpeexportautomobile-cmyk.github.io/buton-sunet-ios/`

**Cloudflare R2** (planul gratuit) merge la fel: încarci aceleași fișiere într-un bucket public și folosești URL-ul bucket-ului.

În aplicație: **Profil → Adresa media** → lipește adresa, fără `manifest.json` la final → Salvează. Trage din nou catalogul cu **Reîncarcă catalogul** dacă vrei imediat. La următoarea deschidere se întâmplă singur.

Un verset intră în manifest doar când are și poză, și sunet. Până atunci rămâne desenul și vocea telefonului. Un capitol nou publicat în manifest apare în feed fără update de aplicație; textul versetului este în manifest.

## Chatul cu personajele

Motorul este **llama.cpp v0.8.0**, compilat în aplicație (CPU, Accelerate). Modelul **nu** este în IPA.

La primul mesaj (sau din butonul din conversație) se descarcă o dată

`Qwen2.5-0.5B-Instruct` Q4_0, aproximativ **410 MB**, de pe Hugging Face. Rămâne în telefon și nu intră în backup-ul iCloud. Întrebarea și versetele nu pleacă pe internet.

Răspunsul este legat de versetele personajului: primele mențiuni plus versetele care seamănă cu întrebarea. Instrucțiunea îi cere să spună când textul nu acoperă întrebarea. Qwen 0.5B este un model mic; poate greși. Un 7B nu încape cuminte în acest fel de IPA, iar variantele Q2 ale aceluiași 0.5B tot au aproape 400 MB din cauza vocabularului, așa că Q4_0 este compromisul. Adresa fișierului GGUF se poate schimba din **Profil → Adresa modelului**.

Personajele din prototip: Dumnezeu, Adam, Eva, Șarpele, Heruvimi. Lista de porecle (de exemplu Adam / omul / om) este în `data/aliases.json`. Scriptul `factory/extract_characters.py` leagă versetele.

## Mai multe cărți

`factory/build_seed.py` taie capitole din JSON-ul Cornilescu complet (`m0ty/bible-io-json`, `Romanian/ron-cornilescu-1924.json`). Fabrica primește orice fișier cu aceeași formă (`--verses`). Publici noul `output/` la aceeași adresă. Aplicația deja instalată vede versetele și personajele noi.

Textul din 1924 este, în Statele Unite, în domeniul public. Sursa copiată aici este fișierul de mai sus, doar Geneza 1–3.
