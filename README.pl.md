*Przeczytaj w innych językach: [English](README.md), [한국어](README.ko.md), [Polski](README.pl.md)*

# ⚡ SwiftDeck: Skróty klawiszowe, automatyzacja promptów i wsparcie raportowania

<p align="center">
  <img src="./assets/demo.gif" width="900" alt="SwiftDeck Demo">
</p>

<p align="center">
  <img src="./assets/swiftdeck_infographic.svg" width="950" alt="SwiftDeck - Architektura techniczna i wydajnosc automatyzacji">
</p>

> **Mapowanie skrótów · Często używane prompty i SQL · Wsparcie przygotowania raportów**

**SwiftDeck** to praktyczne narzędzie desktopowe ułatwiające codzienną pracę biurową i przygotowywanie raportów w zespołach operacyjnych.

W codziennych zadaniach pracownicy wielokrotnie przeszukują te same foldery sieciowe, wprowadzają cykliczne zapytania SQL oraz wklejają powtarzalne teksty. Program łączy te czynności pod wygodnym skrótem klawiszowym (Alt + Space), umożliwiając błyskawiczne otwieranie ścieżek roboczych, wstawianie szablonów raportowych i wykonywanie codziennych kalkulacji bez zbędnych kliknięć myszą.

## Główne funkcje

- **📂 Szybka nawigacja do folderów**: Otwieraj najczęściej używane foldery, ścieżki pobierania ERP, foldery dokumentacji miesięcznej i dyski sieciowe za pomocą menu skrótów. Obsługuje przeglądanie podfolderów do 2 poziomów z inteligentnym buforowaniem (cache).
- **⌨️ Automatyzacja tekstu, promptów i SQL**: Wprowadzaj długie bloki tekstu, zapytania SQL, prompty AI lub sekwencje klawiszy sterujących, takie jak `{Enter}`, `{Tab}`, `{Wait:500}`, `Ctrl+S`.
- **📋 Podręczne menu promptów**: Naciśnij `Shift + Win + Spacja`, aby natychmiast wyświetlić wszystkie zarejestrowane szablony w menu podręcznym przy kursorze myszy — bez konieczności pamiętania numerów skrótów.
- **✏️ Skróty tekstowe (Hotstrings)**: Rozwijaj krótkie zdefiniowane skróty w pełne szablony e-mail, formułki raportowe, symbole lub standardowe komunikaty natychmiast po naciśnięciu spacji lub Enter.
- **🔀 Remapowanie klawiszy**: Przypisz rzadko używane klawisze (np. CapsLock) do praktycznych skrótów, kliknięć myszy lub określonych akcji w pracy.
- **⚙️ Łatwe wdrożenie zespołowe**: Udostępniaj lokalny plik konfiguracyjny `.ini`, aby ujednolicić ścieżki folderów, prompty i szablony w całym dziale bez skomplikowanej instalacji.

---

## 🚀 Pobieranie i instalacja (Instalator One-Click)

**SwiftDeck** jest dystrybuowany jako standardowy instalator użytkownika Windows (**`App02_SwiftDeck_Setup_vX.Y.Z.exe`**), który **nie wymaga uprawnień administratora (UAC)** i instaluje się bez problemu na komputerach firmowych.

### 📥 Instrukcja instalacji

1. Przejdź do zakładki **[Releases](https://github.com/KwangBeomPark/02_SwiftDeck/releases)** na GitHubie.
2. Pobierz najnowszy instalator **`App02_SwiftDeck_Setup_vX.Y.Z.exe`** (oraz towarzyszące pliki manifestu JSON i sum kontrolnych SHA-256).
3. Uruchom pobrany plik. Aplikacja zainstaluje się automatycznie w `%LOCALAPPDATA%\Programs\SwiftDeck`.
4. Ustawienia użytkownika (`UserSetting\config.ini`) są w pełni zachowywane podczas aktualizacji i ponownej instalacji.
5. Uruchom SwiftDeck z menu Start, skrótu na pulpicie lub zasobnika systemowego.

### 🛡️ Informacje o podpisie cyfrowym

Wydania SwiftDeck są opatrzone podpisem cyfrowym Authenticode (SHA-256 ze znacznikiem czasu RFC 3161):
- Wydawca: `Open Source Developer KWANG BEOM PARK`
- Urząd certyfikacji: `Certum Code Signing 2021 CA`

---

## ⌨️ Domyślne skróty klawiszowe

| Skrót | Funkcja |
| :--- | :--- |
| `Win + F` | Otwórz menu szybkiego dostępu do folderów |
| `Shift + Win + Spacja` | Wyświetl podręczne menu promptów przy kursorze myszy |
| `Win + 1` ~ `Win + 9` | Wykonaj przypisany szablon tekstu / prompt / zapytanie SQL |
| `CapsLock` | Domyślnie zremapowany na klawisz funkcyjny (np. Enter lub skrót funkcyjny) |

---

## 📄 Licencja

Projekt jest objęty licencją MIT. Szczegóły w pliku [LICENSE](LICENSE).
