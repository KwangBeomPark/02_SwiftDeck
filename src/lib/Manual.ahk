#Requires AutoHotkey v2.0
#Include Theme.ahk
#Include Config.ahk
#Include Utils.ahk

IsSupportedManualLanguage(langCode) {
    static supportedLanguages := Map(
        "EN", true, "KR", true, "PL", true, "FR", true, "DE", true, "ES", true, "IT", true,
        "GR", true, "PT", true, "CZ", true, "LV", true, "HU", true, "RO", true, "NO", true)
    return supportedLanguages.Has(langCode)
}

GetSavedManualLanguage() {
    savedLanguage := StrUpper(Trim(ConfigReadValue("Settings", "Settings", "ManualLanguage", "EN")))
    return IsSupportedManualLanguage(savedLanguage) ? savedLanguage : "EN"
}

SaveManualLanguage(langCode) {
    if !IsSupportedManualLanguage(langCode)
        return false
    try {
        ConfigWriteValue("Settings", "Settings", "ManualLanguage", langCode)
        return true
    } catch Error as err {
        ToolTip("⚠️ The manual language preference could not be saved.`n" . err.Message)
        SetTimer(() => ToolTip(), -2500)
        return false
    }
}

OpenAppManual(lang := "", parentHwnd := 0) {
    lang := StrUpper(Trim(lang))
    if (lang == "")
        lang := GetSavedManualLanguage()
    else if !IsSupportedManualLanguage(lang)
        lang := "EN"

    mGui := Gui("+AlwaysOnTop +Resize -MaximizeBox", "App Manual")
    if (parentHwnd)
        mGui.Opt("+Owner" . parentHwnd)
    EnableDarkMode(mGui)
    mGui.SetFont("s11", "Segoe UI")

    ; --- Language selection dropdown ---
    mGui.Add("Text", "x10 y10 w80", "Language:")
    langChoices := ["🇺🇸 English", "🇰🇷 한국어", "🇵🇱 Polski", "🇫🇷 Français", "🇩🇪 Deutsch", "🇪🇸 Español", "🇮🇹 Italiano", "🇬🇷 Ελληνικά", "🇵🇹 Português", "🇨🇿 Čeština", "🇱🇻 Latviešu", "🇭🇺 Magyar", "🇷🇴 Română", "🇳🇴 Norsk"]

    ; Determine initial selection index
    langMapRev := Map("EN", 1, "KR", 2, "PL", 3, "FR", 4, "DE", 5, "ES", 6, "IT", 7, "GR", 8, "PT", 9, "CZ", 10, "LV", 11, "HU", 12, "RO", 13, "NO", 14)
    langIdx := langMapRev.Has(lang) ? langMapRev[lang] : 1

    mGui.SetFont("cBlack")
    ddlLang := mGui.Add("DropDownList", "x95 y7 w140 Choose" . langIdx, langChoices)
    mGui.SetFont("c" . THEME_TEXT)

    ; --- Content area ---
    ; Helper: returns localized text for the given language
    GetManualTexts(langCode) {
        if (langCode == "KR") {
            return {
                tab1: "🚀 퀵 스타트 (기본 사용법)",
                tab2: "⚙️ 앱 설정 (App Settings)",
                part1: "
                (
                    **1. 📂 1초 만에 폴더 열기 (기본 단축키: F1)**`n    - 아무 화면에서나 F1 키를 누르면 내가 저장한 폴더 목록이 짠! 나타남`n    - 폴더탐색기에서 Ctrl+F1을 누르면 지금 보는 폴더를 바로 내 폴더 목록에 추가할 수 있음`n**2. ⌨️ 마법의 자동 타이핑 (기본 단축키: Win + 숫자 0~9)**`n    - 자주 쓰는 긴 문장이나 이메일 양식, 메일주소, AI 프롬프트 등 입력`n    - Win 키와 숫자를 같이 누르면 미리 저장한 문장이 입력`n**3. ✨ Symbol 메뉴 & Symbol 자동 변환 (단축키: Ctrl + Win + 스페이스바)**`n    - 복잡한 기호 찾지 말고 메뉴를 열어서 선택!`n    - '자동 변환'도 있어요! 예를 들어 '_usd'라고 치면 '$'로 변경됨`n**4. 🔀 키보드 내 맘대로 바꾸기 (키 매핑)**`n    - 잘 안 쓰는 'Caps Lock' 키를 다른 키로 바꿔서 내 손에 딱 맞게 커스텀 할 수 있음
                )",
                part2: "
                (
                    - App Settings: 모든 기능을 쉽고 편하게 관리`n**1. 📁 [Folders] 탭, ⌨️ [Prompts] 탭**`n    - 추가(+), 수정(✏️), 지우기(x) 버튼으로 내 입맛대로 리스트를 정리`n**2. ✏️ [Hotstrings] 탭, 🔀 [Key Remap] 탭**`n    - [Hotstrings] 탭에서 나만의 단축어 추가`n    - [Key Remap] 탭에서는 안 쓰는 키를 새롭게 맵핑`n**3. ⚙️ [General] 탭**`n    - 단축키 변경, Windows 자동 시작, 설정 폴더 열기, 백업 및 복원을 한곳에서 관리`n**4. 💾 저장과 복구**`n    - Folders/Prompts/Hotstrings/Key Remap 변경은 작업 확인 즉시 저장·적용`n    - 여러 단축키 값을 함께 조정하는 General만 [Save & Apply] 사용`n    - [Backup Saved]는 현재 디스크에 저장된 설정을 백업
                )"
            }
        } else if (langCode == "PL") {
            return {
                tab1: "🚀 Szybki Start",
                tab2: "⚙️ Ustawienia Aplikacji",
                part1: "
                (
                    **1. 📂 Otwórz Foldery w 1 Sekundę (Domyślny skrót: F1)**`n    - Naciśnij F1 w dowolnym miejscu, a natychmiast pojawi się menu Twoich folderów!`n    - Naciśnij Ctrl+F1 w Eksploratorze, aby dodać bieżący folder do listy.`n**2. ⌨️ Magiczne Autouzupełnianie (Domyślny skrót: Win + Numpad 0~9)**`n    - Przestań ręcznie wpisywać częste e-maile czy adresy.`n    - Naciśnij Win + Numpad, aby automatycznie wpisać zapisany tekst.`n**3. ✨ Menu Symboli i Auto-Zamiana (Skrót: Ctrl + Win + Spacja)**`n    - Koniec z szukaniem symboli; otwórz menu i wybierz!`n    - Wypróbuj 'Auto-Zamianę'! Wpisanie '_usd' zmienia się w '$'.`n**4. 🔀 Zmień Klawisze (Mapowanie Klawiszy)**`n    - Zmień rzadko używane klawisze, aby idealnie pasowały do Twoich rąk!
                )",
                part2: "
                (
                    - App Settings: Łatwe zarządzanie wszystkimi funkcjami`n**1. 📁 Zakładka [Folders], ⌨️ Zakładka [Prompts]**`n    - Organizuj swoje listy za pomocą przycisków Dodaj (+), Edytuj (✏️) i Usuń (x).`n**2. ✏️ Zakładka [Hotstrings], 🔀 Zakładka [Key Remap]**`n    - Dodaj własne skróty tekstowe w [Hotstrings].`n    - Zmień rzadko używane klawisze na nowe funkcje w [Key Remap].`n**3. ⚙️ Zakładka [General]**`n    - Nie podobają Ci się domyślne skróty aplikacji? Zmień je!
                )"
            }
        } else if (langCode == "FR") {
            return {
                tab1: "🚀 Démarrage Rapide",
                tab2: "⚙️ Paramètres",
                part1: "
                (
                    **1. 📂 Ouvrir les Dossiers en 1 Seconde (Raccourci: F1)**`n    - Appuyez sur F1 pour faire apparaître vos dossiers favoris !`n    - Appuyez sur Ctrl+F1 dans l'Explorateur pour ajouter le dossier actuel.`n**2. ⌨️ Saisie Magique (Raccourci: Win + Pavé Num. 0~9)**`n    - Ne tapez plus vos e-mails ou adresses manuellement.`n    - Appuyez sur Win + Num pour taper automatiquement votre texte.`n**3. ✨ Menu Symboles & Remplacement Auto (Raccourci: Ctrl + Win + Espace)**`n    - Ne cherchez plus vos symboles ; ouvrez le menu et choisissez !`n    - Essayez le remplacement : tapez '_usd' pour insérer '$'.`n**4. 🔀 Remappage Clavier (Key Mapping)**`n    - Changez les touches peu utiles pour les adapter à vos besoins !
                )",
                part2: "
                (
                    - App Settings : Gérez facilement toutes vos fonctionnalités`n**1. 📁 Onglets [Folders] & ⌨️ [Prompts]**`n    - Organisez vos listes avec les boutons Ajouter (+), Éditer (✏️) et Supprimer (x).`n**2. ✏️ Onglets [Hotstrings] & 🔀 [Key Remap]**`n    - Ajoutez vos propres raccourcis texte dans [Hotstrings].`n    - Remappez les touches inutilisées dans [Key Remap].`n**3. ⚙️ Onglet [General]**`n    - Changez les raccourcis par défaut de l'application à votre guise !
                )"
            }
        } else if (langCode == "DE") {
            return {
                tab1: "🚀 Schnellstart",
                tab2: "⚙️ Einstellungen",
                part1: "
                (
                    **1. 📂 Ordner in 1 Sekunde öffnen (Standard: F1)**`n    - Drücken Sie überall F1, und Ihre Ordnerliste erscheint!`n    - Drücken Sie Strg+F1 im Explorer, um den aktuellen Ordner hinzuzufügen.`n**2. ⌨️ Magisches Auto-Tippen (Standard: Win + Numpad 0~9)**`n    - Tippen Sie häufige E-Mails nicht mehr von Hand.`n    - Drücken Sie Win + Numpad, um Text automatisch einzufügen.`n**3. ✨ Symbol-Menü & Auto-Ersetzen (Standard: Strg + Win + Leerzeichen)**`n    - Suchen Sie nicht nach Symbolen; öffnen Sie das Menü und wählen Sie!`n    - Probieren Sie 'Auto-Ersetzen'! Tippen Sie '_usd' für '$'.`n**4. 🔀 Tastatur-Neubelegung (Key Mapping)**`n    - Ändern Sie selten genutzte Tasten nach Ihren Wünschen!
                )",
                part2: "
                (
                    - App Settings: Verwalten Sie alle Funktionen ganz einfach`n**1. 📁 [Folders]-Tab & ⌨️ [Prompts]-Tab**`n    - Organisieren Sie Ihre Listen mit Hinzufügen (+), Bearbeiten (✏️) und Löschen (x).`n**2. ✏️ [Hotstrings]-Tab & 🔀 [Key Remap]-Tab**`n    - Fügen Sie in [Hotstrings] eigene Textkürzel hinzu.`n    - Weisen Sie ungenutzten Tasten in [Key Remap] neue Funktionen zu.`n**3. ⚙️ [General]-Tab**`n    - Ändern Sie die Standard-Hotkeys der App nach Belieben!
                )"
            }
        } else if (langCode == "ES") {
            return {
                tab1: "🚀 Inicio Rápido",
                tab2: "⚙️ Configuración",
                part1: "
                (
                    **1. 📂 Abrir Carpetas en 1 Segundo (Atajo: F1)**`n    - ¡Presione F1 en cualquier lugar y aparecerán sus carpetas guardadas!`n    - Presione Ctrl+F1 en el Explorador para agregar la carpeta actual.`n**2. ⌨️ Escritura Mágica (Atajo: Win + Numpad 0~9)**`n    - Deje de escribir correos frecuentes a mano.`n    - Presione Win + Número para escribir automáticamente el texto guardado.`n**3. ✨ Menú de Símbolos y Auto-Reemplazo (Atajo: Ctrl + Win + Espacio)**`n    - ¡No busque símbolos complejos; abra el menú y seleccione!`n    - Pruebe el 'Auto-Reemplazo': escriba '_usd' para convertirlo en '$'.`n**4. 🔀 Reasignación de Teclado (Key Mapping)**`n    - ¡Cambie teclas poco usadas para adaptarlas a sus manos!
                )",
                part2: "
                (
                    - App Settings: Administre todas las funciones fácilmente`n**1. 📁 Pestaña [Folders], ⌨️ Pestaña [Prompts]**`n    - Organice sus listas con los botones Agregar (+), Editar (✏️) y Eliminar (x).`n**2. ✏️ Pestaña [Hotstrings], 🔀 Pestaña [Key Remap]**`n    - Agregue sus propios atajos de texto en [Hotstrings].`n    - Reasigne teclas no utilizadas en [Key Remap].`n**3. ⚙️ Pestaña [General]**`n    - ¿No le gustan los atajos predeterminados? ¡Cámbielos a los que prefiera!
                )"
            }
        } else if (langCode == "IT") {
            return {
                tab1: "🚀 Avvio Rapido",
                tab2: "⚙️ Impostazioni",
                part1: "
                (
                    **1. 📂 Apri Cartelle in 1 Secondo (Scorciatoia: F1)**`n    - Premi F1 ovunque e appariranno le tue cartelle preferite!`n    - Premi Ctrl+F1 in Explorer per aggiungere subito la cartella corrente.`n**2. ⌨️ Digitazione Magica (Scorciatoia: Win + Tastierino 0~9)**`n    - Smetti di digitare a mano e-mail o messaggi frequenti.`n    - Premi Win + Numero per inserire automaticamente il testo salvato.`n**3. ✨ Menu Simboli & Auto-Sostituzione (Scorciatoia: Ctrl + Win + Spazio)**`n    - Non cercare simboli complessi; apri il menu e scegli!`n    - Prova 'Auto-Sostituzione'! Digitando '_usd' si trasforma in '$'.`n**4. 🔀 Rimappatura Tastiera (Key Mapping)**`n    - Cambia i tasti poco usati per adattarli alle tue esigenze!
                )",
                part2: "
                (
                    - App Settings: Gestisci tutte le funzionalità facilmente`n**1. 📁 Scheda [Folders], ⌨️ Scheda [Prompts]**`n    - Organizza le tue liste con i pulsanti Aggiungi (+), Modifica (✏️) ed Elimina (x).`n**2. ✏️ Scheda [Hotstrings], 🔀 Scheda [Key Remap]**`n    - Aggiungi scorciatoie di testo in [Hotstrings].`n    - Assegna nuove funzioni ai tasti inutilizzati in [Key Remap].`n**3. ⚙️ Scheda [General]**`n    - Cambia le scorciatoie dell'app come preferisci!
                )"
            }
        } else if (langCode == "GR") {
            return {
                tab1: "🚀 Γρήγορη Εκκίνηση",
                tab2: "⚙️ Ρυθμίσεις",
                part1: "
                (
                    **1. 📂 Άνοιγμα Φακέλων σε 1 Δευτερόλεπτο (Προεπιλογή: F1)**`n    - Πατήστε F1 οπουδήποτε για να εμφανιστούν οι φάκελοί σας!`n    - Πατήστε Ctrl+F1 στην Εξερεύνηση για να προσθέσετε τον τρέχοντα φάκελο.`n**2. ⌨️ Μαγική Πληκτρολόγηση (Προεπιλογή: Win + Numpad 0~9)**`n    - Σταματήστε να πληκτρολογείτε συχνά email με το χέρι.`n    - Πατήστε Win + Αριθμό για να εισαχθεί αυτόματα το κείμενο.`n**3. ✨ Μενού Συμβόλων & Αυτόματη Αντικατάσταση (Ctrl + Win + Space)**`n    - Μην ψάχνετε σύμβολα. Ανοίξτε το μενού και επιλέξτε!`n    - Πληκτρολογήστε '_usd' και θα μετατραπεί σε '$'.`n**4. 🔀 Αλλαγή Πλήκτρων (Key Mapping)**`n    - Αλλάξτε πλήκτρα όπως το 'Caps Lock' στα μέτρα σας!
                )",
                part2: "
                (
                    - App Settings: Εύκολη διαχείριση όλων των λειτουργιών`n**1. 📁 Καρτέλα [Folders], ⌨️ Καρτέλα [Prompts]**`n    - Οργανώστε τις λίστες σας με Προσθήκη (+), Επεξεργασία (✏️), Διαγραφή (x).`n**2. ✏️ Καρτέλα [Hotstrings], 🔀 Καρτέλα [Key Remap]**`n    - Προσθέστε δικές σας συντομεύσεις κειμένου στο [Hotstrings].`n    - Αλλάξτε λειτουργίες πλήκτρων στο [Key Remap].`n**3. ⚙️ Καρτέλα [General]**`n    - Αλλάξτε τις συντομεύσεις της εφαρμογής (π.χ. F1, Win) όπως θέλετε!
                )"
            }
        } else if (langCode == "PT") {
            return {
                tab1: "🚀 Início Rápido",
                tab2: "⚙️ Configurações",
                part1: "
                (
                    **1. 📂 Abrir Pastas em 1 Segundo (Atalho: F1)**`n    - Pressione F1 em qualquer lugar e suas pastas salvas aparecerão!`n    - Pressione Ctrl+F1 no Explorer para adicionar a pasta atual.`n**2. ⌨️ Digitação Mágica (Atalho: Win + NumPad 0~9)**`n    - Pare de digitar e-mails frequentes manualmente.`n    - Pressione Win + Número para colar automaticamente o texto salvo.`n**3. ✨ Menu de Símbolos e Auto-Substituir (Atalho: Ctrl + Win + Espaço)**`n    - Não procure símbolos complexos; abra o menu e escolha!`n    - Digitar '_usd' se transforma magicamente em '$'.`n**4. 🔀 Remapear Teclado (Key Mapping)**`n    - Mude teclas pouco usadas para se adequar às suas mãos!
                )",
                part2: "
                (
                    - App Settings: Gerencie todos os recursos facilmente`n**1. 📁 Aba [Folders], ⌨️ Aba [Prompts]**`n    - Organize suas listas com botões Adicionar (+), Editar (✏️) e Excluir (x).`n**2. ✏️ Aba [Hotstrings], 🔀 Aba [Key Remap]**`n    - Adicione seus atalhos de texto na aba [Hotstrings].`n    - Remapeie teclas não usadas na aba [Key Remap].`n**3. ⚙️ Aba [General]**`n    - Mude os atalhos padrão do app como preferir!
                )"
            }
        } else if (langCode == "CZ") {
            return {
                tab1: "🚀 Rychlý Start",
                tab2: "⚙️ Nastavení",
                part1: "
                (
                    **1. 📂 Otevřete složky za 1 sekundu (Výchozí: F1)**`n    - Stiskněte F1 kdekoli a okamžitě se objeví menu složek!`n    - Stisknutím Ctrl+F1 v Průzkumníkovi přidáte aktuální složku.`n**2. ⌨️ Magické psaní (Výchozí: Win + Numpad 0~9)**`n    - Přestaňte ručně psát časté e-maily.`n    - Stiskněte Win + číslo pro automatické vložení textu.`n**3. ✨ Menu symbolů a automatické nahrazení (Ctrl + Win + Mezerník)**`n    - Už žádné hledání symbolů; otevřete menu a vyberte!`n    - Zkuste '_usd' a magicky se to změní na '$'.`n**4. 🔀 Přebudování klávesnice (Key Mapping)**`n    - Změňte málo používané klávesy jako 'Caps Lock'!
                )",
                part2: "
                (
                    - App Settings: Snadná správa všech funkcí`n**1. 📁 Karta [Folders], ⌨️ Karta [Prompts]**`n    - Organizujte své seznamy pomocí Přidat (+), Upravit (✏️) a Smazat (x).`n**2. ✏️ Karta [Hotstrings], 🔀 Karta [Key Remap]**`n    - Přidejte vlastní textové zkratky v [Hotstrings].`n    - Změňte nepoužívané klávesy v [Key Remap].`n**3. ⚙️ Karta [General]**`n    - Změňte výchozí klávesové zkratky aplikace podle sebe!
                )"
            }
        } else if (langCode == "LV") {
            return {
                tab1: "🚀 Ātrais Starts",
                tab2: "⚙️ Iestatījumi",
                part1: "
                (
                    **1. 📂 Atvērt mapes 1 sekundē (Noklusējums: F1)**`n    - Nospiediet F1 jebkur, un parādīsies jūsu mapju izvēlne!`n    - Nospiediet Ctrl+F1 Pārlūkā, lai pievienotu pašreizējo mapi.`n**2. ⌨️ Maģiskā rakstīšana (Noklusējums: Win + Numpad 0~9)**`n    - Beidziet manuāli rakstīt bieži lietotus e-pastus.`n    - Nospiediet Win + ciparu, lai automātiski ievietotu tekstu.`n**3. ✨ Simbolu izvēlne un Auto-aizvietošana (Ctrl + Win + Atstarpe)**`n    - Nemeklējiet simbolus; atveriet izvēlni un izvēlieties!`n    - Ierakstot '_usd', tas maģiski pārvērtīsies par '$'.`n**4. 🔀 Tastatūras pārveidošana (Key Mapping)**`n    - Mainiet reti izmantotos taustiņus kā 'Caps Lock'!
                )",
                part2: "
                (
                    - App Settings: Viegli pārvaldiet visas funkcijas`n**1. 📁 [Folders] cilne, ⌨️ [Prompts] cilne**`n    - Organizējiet sarakstus ar Pievienot (+), Rediģēt (✏️) un Dzēst (x).`n**2. ✏️ [Hotstrings] cilne, 🔀 [Key Remap] cilne**`n    - Pievienojiet savus teksta saīsinājumus [Hotstrings].`n    - Mainiet neizmantotos taustiņus [Key Remap].`n**3. ⚙️ [General] cilne**`n    - Mainiet lietotnes noklusējuma saīsnes pēc saviem ieskatiem!
                )"
            }
        } else if (langCode == "HU") {
            return {
                tab1: "🚀 Gyors Kezdés",
                tab2: "⚙️ Beállítások",
                part1: "
                (
                    **1. 📂 Mappák megnyitása 1 másodperc alatt (Alapértelmezett: F1)**`n    - Nyomja meg az F1-et bárhol, és megjelenik a mappamenü!`n    - Nyomja meg a Ctrl+F1-et az Intézőben az aktuális mappa hozzáadásához.`n**2. ⌨️ Varázslatos gépelés (Alapértelmezett: Win + Numpad 0~9)**`n    - Ne gépelje be kézzel a gyakori e-maileket.`n    - Nyomja meg a Win + számot az előre mentett szöveg beírásához.`n**3. ✨ Szimbólum menü és Automatikus Csere (Ctrl + Win + Szóköz)**`n    - Ne keressen szimbólumokat; nyissa meg a menüt és válasszon!`n    - Próbálja ki az 'Automatikus cserét'! Írja be az '_usd'-t, és '$' lesz belőle.`n**4. 🔀 Billentyűzet Átrendezése (Key Mapping)**`n    - Változtassa meg a ritkán használt billentyűket, mint a 'Caps Lock'!
                )",
                part2: "
                (
                    - App Settings: Kezeljen minden funkciót egyszerűen`n**1. 📁 [Folders] fül, ⌨️ [Prompts] fül**`n    - Rendszerezze listáit a Hozzáadás (+), Szerkesztés (✏️) és Törlés (x) gombokkal.`n**2. ✏️ [Hotstrings] fül, 🔀 [Key Remap] fül**`n    - Adja hozzá saját szöveges rövidítéseit a [Hotstrings] fülön.`n    - Rendeljen új funkciót a nem használt billentyűkhöz a [Key Remap] fülön.`n**3. ⚙️ [General] fül**`n    - Változtassa meg az alkalmazás gyorsbillentyűit, ahogy csak akarja!
                )"
            }
        } else if (langCode == "RO") {
            return {
                tab1: "🚀 Start Rapid",
                tab2: "⚙️ Setări",
                part1: "
                (
                    **1. 📂 Deschide Foldere în 1 Secundă (Comandă: F1)**`n    - Apasă F1 oriunde și va apărea meniul tău de foldere!`n    - Apasă Ctrl+F1 în Explorer pentru a adăuga folderul curent.`n**2. ⌨️ Tastare Magică (Comandă: Win + Numpad 0~9)**`n    - Nu mai tasta manual e-mailurile frecvente.`n    - Apasă Win + Număr pentru a insera automat textul salvat.`n**3. ✨ Meniu Simboluri & Auto-Înlocuire (Ctrl + Win + Spațiu)**`n    - Nu mai căuta simboluri; deschide meniul și selectează!`n    - Tastând '_usd' se va transforma magic în '$'.`n**4. 🔀 Remapare Tastatură (Key Mapping)**`n    - Schimbă tastele rar folosite precum 'Caps Lock'!
                )",
                part2: "
                (
                    - App Settings: Gestionează toate funcțiile cu ușurință`n**1. 📁 Tab [Folders], ⌨️ Tab [Prompts]**`n    - Organizează listele cu butoanele Adaugă (+), Editează (✏️), Șterge (x).`n**2. ✏️ Tab [Hotstrings], 🔀 Tab [Key Remap]**`n    - Adaugă scurtături de text în tab-ul [Hotstrings].`n    - Remapează tastele nefolosite în tab-ul [Key Remap].`n**3. ⚙️ Tab [General]**`n    - Schimbă scurtăturile aplicației după preferințe!
                )"
            }
        } else if (langCode == "NO") {
            return {
                tab1: "🚀 Hurtigstart",
                tab2: "⚙️ Innstillinger",
                part1: "
                (
                    **1. 📂 Åpne mapper på 1 sekund (Standard: F1)**`n    - Trykk F1 hvor som helst for å åpne mappemenyen!`n    - Trykk Ctrl+F1 i Utforsker for å legge til gjeldende mappe.`n**2. ⌨️ Magisk autotyping (Standard: Win + Numpad 0~9)**`n    - Slutt å skrive vanlige e-poster manuelt.`n    - Trykk Win + Nummer for å sette inn lagret tekst automatisk.`n**3. ✨ Symbolmeny & Auto-erstatt (Ctrl + Win + Mellomrom)**`n    - Ikke let etter symboler; åpne menyen og velg!`n    - Prøv 'Auto-erstatt'! Skriver du '_usd' blir det til '$'.`n**4. 🔀 Endre tastatur (Key Mapping)**`n    - Bytt ut lite brukte taster som 'Caps Lock'!
                )",
                part2: "
                (
                    - App Settings: Administrer alle funksjoner enkelt`n**1. 📁 [Folders]-fane, ⌨️ [Prompts]-fane**`n    - Organiser listene dine med Legg til (+), Rediger (✏️) og Slett (x).`n**2. ✏️ [Hotstrings]-fane, 🔀 [Key Remap]-fane**`n    - Legg til dine egne tekstsnarveier i [Hotstrings].`n    - Gi ubrukte taster nye funksjoner i [Key Remap].`n**3. ⚙️ [General]-fane**`n    - Endre appens snarveier som du vil!
                )"
            }
        } else { ; EN (default)
            return {
                tab1: "🚀 Quick Start",
                tab2: "⚙️ App Settings",
                part1: "
                (
                    **1. 📂 Open Folders in 1 Second (Default Hotkey: F1)**`n    - Press F1 anywhere and your saved folders menu will instantly appear!`n    - Press Ctrl+F1 in Explorer to add the current folder directly to your list.`n**2. ⌨️ Magical Auto-Typing (Default Hotkey: Win + Numpad 0~9)**`n    - Stop typing your frequent emails, AI prompts, or addresses manually.`n    - Press Win + Numpad to automatically type your predefined text.`n**3. ✨ Symbol Menu & Auto-Replace (Hotkey: Ctrl + Win + Space)**`n    - No more searching for complex symbols; just open the menu and select!`n    - Try 'Auto-Replace'! For example, typing '_usd' magically transforms into '$'.`n**4. 🔀 Remap Your Keyboard (Key Mapping)**`n    - Change rarely used keys like 'Caps Lock' to suit your hands perfectly!
                )",
                part2: "
                (
                    - App Settings: Manage all your features easily`n**1. 📁 [Folders] Tab, ⌨️ [Prompts] Tab**`n    - Organize your lists exactly as you want with Add (+), ✏️ Edit, and Delete (x) buttons.`n**2. ✏️ [Hotstrings] Tab, 🔀 [Key Remap] Tab**`n    - Add your custom text expansions in the [Hotstrings] tab.`n    - Remap unused keys to new functions in the [Key Remap] tab.`n**3. ⚙️ [General] Tab**`n    - Manage hotkeys, Windows startup, the settings folder, backup, and restore in one place.`n**4. 💾 Save and Recovery**`n    - Folders, Prompts, Hotstrings, and Key Remap save and apply each confirmed action immediately.`n    - Only General uses [Save & Apply] because its hotkey values are edited together.`n    - [Backup Saved] captures the configuration currently stored on disk.
                )"
            }
        }
    }

    GetManualShortcutSummary(langCode) {
        settings := ConfigReadAppSettings()
        if (settings.PromptModifier == "") {
            promptRange := "Disabled"
        } else {
            promptPrefix := FormatHotkeyDisplay(settings.PromptModifier) . (settings.PromptUseNumpad ? "Num" : "")
            promptRange := promptPrefix . "0 ~ " . promptPrefix . "9"
        }
        heading := langCode == "KR" ? "현재 적용된 단축키" : "Current Shortcuts"
        return "**" . heading . "**`n"
            . "    - Favorites: " . FormatHotkeyDisplay(settings.MainHotkey) . " | Add Current Folder: " . FormatHotkeyDisplay(GetAddFolderHotkey(settings.MainHotkey)) . "`n"
            . "    - Quick Prompts: " . promptRange . " | Popup Menu: " . FormatHotkeyDisplay(GetPromptMenuHotkey()) . "`n"
            . "    - Emoji & Symbols: " . FormatHotkeyDisplay(settings.EmojiHotkey) . " | Exit: " . FormatHotkeyDisplay(settings.ExitHotkey)
    }

    BuildManualText(langCode, texts) {
        return GetManualShortcutSummary(langCode) . "`n`n"
            . texts.tab1 . "`n" . texts.part1 . "`n`n"
            . texts.tab2 . "`n" . texts.part2
    }

    ; HTML conversion and blue highlight helper
    FormatTextToHtml(txt) {
        ; HTML special character encoding
        txt := StrReplace(txt, "&", "&amp;")
        txt := StrReplace(txt, "<", "&lt;")
        txt := StrReplace(txt, ">", "&gt;")

        ; Markdown bold (**text**) processing
        txt := RegExReplace(txt, "\*\*([^\*]+)\*\*", "<b>$1</b>")

        ; Newline handling
        txt := StrReplace(txt, "`r`n", "<br>")
        txt := StrReplace(txt, "`n", "<br>")
        txt := StrReplace(txt, "`r", "<br>")

        ; Indentation whitespace handling
        txt := StrReplace(txt, "    ", "&nbsp;&nbsp;&nbsp;&nbsp;")

        ; Style text inside parentheses with blue (#0056b3) and bold
        txt := RegExReplace(txt, "\(([^)]+)\)", "<span style='color:#0056b3; font-weight:bold;'>($1)</span>")

        htmlStr := "<!DOCTYPE html>`n<html>`n<head>`n<meta http-equiv='X-UA-Compatible' content='IE=edge'>`n"
        htmlStr .= "<style>`n"
        htmlStr .= "html, body { margin: 0; padding: 0; border: 0; background-color: #ffffff; overflow-y: auto; overflow-x: hidden; }`n"
        htmlStr .= "body { font-family: 'Segoe UI', 'Malgun Gothic', sans-serif; font-size: 11pt; color: #333333; line-height: 1.55; }`n"
        htmlStr .= "</style>`n</head>`n<body>`n" . txt . "`n</body>`n</html>"

        return htmlStr
    }

    ; Load initial text content
    texts := GetManualTexts(lang)

    ; Create ActiveX HTMLFile control for rich text display. Some managed PCs
    ; block ActiveX by policy, and an unguarded failure here would take the whole
    ; manual window with it — so fall back to a plain read-only Edit.
    edtManual := ""
    try {
        edtManual := mGui.Add("ActiveX", "x10 y40 w670 h640", "htmlfile")
        doc := edtManual.Value
        doc.write(FormatTextToHtml(BuildManualText(lang, texts)))
        doc.close()
    } catch {
        edtManual := ""
        mGui.Add("Edit", "x10 y40 w670 h640 ReadOnly Multi", BuildManualText(lang, texts))
    }

    ; --- Dynamic update on language change ---
    ddlLang.OnEvent("Change", OnLangChange)
    OnLangChange(*) {
        langMap := Map(1, "EN", 2, "KR", 3, "PL", 4, "FR", 5, "DE", 6, "ES", 7, "IT", 8, "GR", 9, "PT", 10, "CZ", 11, "LV", 12, "HU", 13, "RO", 14, "NO")
        newLang := langMap[ddlLang.Value]
        newTexts := GetManualTexts(newLang)
        SaveManualLanguage(newLang)

        ; Nothing to re-render when the rich control could not be created.
        if (edtManual == "")
            return
        doc := edtManual.Value
        doc.open()
        doc.write(FormatTextToHtml(BuildManualText(newLang, newTexts)))
        doc.close()
    }

    btnClose := mGui.Add("Button", "w100 x295 y+15 Default", "Close")
    btnClose.OnEvent("Click", (*) => mGui.Destroy())
    ShowCenteredOnMouse(mGui)
}
