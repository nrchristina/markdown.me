# Тексты сайта

Отсюда лендинг (MD-25) берёт тексты. Английский — основной язык сайта, русский — перевод с той же структурой. Разделы совпадают с секциями лендинга: meta, hero, фичи, скриншоты, FAQ, footer.

## Правила

- **Тон рабочего инструмента.** Факты о том, что приложение делает, без «быстрый», «красивый», «удобный» и восклицательных знаков.
- **Только то, что есть в плане.** Если фичу убирают из MVP (`docs/PLAN.md`), её убирают и отсюда.
- **Название** всегда `Markdown.me`, с точкой.
- **Сочетания клавиш** пишутся символами: ⌘B, ⌘⇧X.
- **Названия элементов интерфейса** совпадают со строками приложения. После MD-18 сверить с `en.lproj` и `ru.lproj`:

  | English | Русский |
  |---|---|
  | text view | вид «Текст» |
  | Markdown view | вид «Markdown» |
  | Settings | Настройки |
  | Check for Updates… | Проверить обновления… |
  | Download for Mac | Скачать для Mac |

---

## English

### Meta

- **Title:** Markdown.me — Markdown editor for Mac
- **Description** (up to 160 characters): A native Markdown editor for macOS. Two views of the same plain .md file: formatted text and Markdown source. Folders, PDF export. Free.

### Hero

- **Heading:** Markdown.me
- **Tagline:** Write formatted text. Keep plain Markdown files.
- **Text:** A native macOS editor with two views of the same file: one hides the Markdown syntax and shows the formatting, the other shows the source.
- **Button:** Download for Mac
- **Under the button:** Free · macOS 14 or later · Apple Silicon and Intel
- **Link:** Source code on GitHub

### Features

1. **Two views, one file.** The text view hides the syntax and shows the formatting. The Markdown view shows the source with highlighting. Switch with ⌘/; the file doesn't change.
2. **Formatting from the keyboard.** ⌘B, ⌘I and ⌘⇧X for bold, italic and strikethrough, ⌘1–⌘3 for headings, ⌘K for links. Lists, checklists, quotes, code and images are in the toolbar.
3. **Folders as workspaces.** Open a folder and work with its files from the sidebar, several at once. Changes made by other apps or by git are picked up.
4. **PDF export.** ⌘E saves the document as a PDF.
5. **Color and size.** Change the color and size of text. They are stored as inline HTML, so the file is still valid Markdown.
6. **Nothing to sign up for.** No account, license key or telemetry. Your documents stay on your Mac.

### Screenshots

Placeholders until MD-28.

- Text view, light theme. **Alt:** A Markdown document in the Markdown.me text view, light theme, with the file sidebar on the left.
- Markdown view, dark theme. **Alt:** The same document in the Markdown view with syntax highlighting, dark theme.

### FAQ

**Why isn't it in the Mac App Store?**
It's distributed directly: updates ship as soon as they're ready, and the app opens your folders without App Store sandbox restrictions. It is still signed with an Apple Developer ID and notarized by Apple, so macOS opens it without warnings.

**How does it update?**
Markdown.me checks GitHub for new versions and asks before installing one. Updates are signed, and the app won't install one whose signature doesn't match. You can turn automatic checks off in Settings and use Check for Updates… in the app menu instead.

**Does it send my documents anywhere?**
No. There is no account, analytics or telemetry. The app contacts GitHub to check for updates, and loads images from the web if a document shows them.

**What are the system requirements?**
macOS 14 Sonoma or later, on a Mac with Apple Silicon or Intel.

**Is it free?**
Yes. No account, no license key.

**Which Markdown does it support?**
CommonMark with the GitHub extensions: tables, strikethrough and task lists. Files are saved as plain .md, so any other editor can open them. For now the text view shows tables as Markdown source.

**Is there a Windows version?**
Not yet. The Mac version comes first; Windows is planned after it.

### Footer

- Source code on GitHub
- Support the project *(shown only once a support link exists)*

---

## Русский

### Meta

- **Title:** Markdown.me — Markdown-редактор для Mac
- **Description** (до 160 символов): Нативный Markdown-редактор для macOS. Два вида одного .md-файла: текст с форматированием и исходник. Папки, экспорт в PDF. Бесплатно.

### Hero

- **Заголовок:** Markdown.me
- **Слоган:** Пишите с форматированием. Храните обычный Markdown.
- **Текст:** Нативный редактор для macOS с двумя видами одного файла: один прячет разметку Markdown и показывает форматирование, другой показывает исходник.
- **Кнопка:** Скачать для Mac
- **Под кнопкой:** Бесплатно · macOS 14 и новее · Apple Silicon и Intel
- **Ссылка:** Исходный код на GitHub

### Фичи

1. **Два вида одного файла.** Вид «Текст» прячет разметку и показывает форматирование. Вид «Markdown» показывает исходник с подсветкой. Переключение — ⌘/, файл при этом не меняется.
2. **Форматирование с клавиатуры.** ⌘B, ⌘I и ⌘⇧X — жирный, курсив и зачёркнутый, ⌘1–⌘3 — заголовки, ⌘K — ссылка. Списки, чек-листы, цитаты, код и картинки — в тулбаре.
3. **Папки как рабочие пространства.** Откройте папку и работайте с её файлами из боковой панели, с несколькими сразу. Изменения из других программ и git подхватываются.
4. **Экспорт в PDF.** ⌘E сохраняет документ в PDF.
5. **Цвет и размер.** Меняйте цвет и размер текста. Они хранятся как встроенный HTML, так что файл остаётся корректным Markdown.
6. **Без регистрации.** Ни аккаунта, ни лицензионного ключа, ни телеметрии. Документы остаются на вашем Mac.

### Скриншоты

Плейсхолдеры до MD-28.

- Вид «Текст», светлая тема. **Alt:** Документ Markdown в виде «Текст» в Markdown.me, светлая тема, слева боковая панель с файлами.
- Вид «Markdown», тёмная тема. **Alt:** Тот же документ в виде «Markdown» с подсветкой синтаксиса, тёмная тема.

### FAQ

**Почему не в Mac App Store?**
Приложение распространяется напрямую: обновления выходят сразу, как готовы, и оно открывает ваши папки без ограничений песочницы App Store. При этом оно подписано сертификатом Apple Developer ID и нотаризовано Apple, поэтому macOS открывает его без предупреждений.

**Как оно обновляется?**
Markdown.me проверяет новые версии на GitHub и спрашивает, прежде чем установить. Обновления подписаны, и обновление с неверной подписью приложение не установит. Автоматическую проверку можно выключить в Настройках и проверять вручную через «Проверить обновления…» в меню приложения.

**Отправляет ли оно куда-то мои документы?**
Нет. Ни аккаунта, ни аналитики, ни телеметрии. Приложение обращается к GitHub, чтобы проверить обновления, и загружает картинки из интернета, если они есть в документе.

**Какие системные требования?**
macOS 14 Sonoma или новее, Mac на Apple Silicon или Intel.

**Это бесплатно?**
Да. Без аккаунта и лицензионного ключа.

**Какой Markdown поддерживается?**
CommonMark с расширениями GitHub: таблицы, зачёркивание и списки задач. Файлы сохраняются как обычные .md, их откроет любой другой редактор. Пока что вид «Текст» показывает таблицы исходником Markdown.

**Есть ли версия для Windows?**
Пока нет. Сначала выходит версия для Mac, Windows запланирована после неё.

### Footer

- Исходный код на GitHub
- Поддержать проект *(только когда появится ссылка поддержки)*
