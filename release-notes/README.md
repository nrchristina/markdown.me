# Release notes

Одна версия — один файл: `release-notes/<version>.md`, например `release-notes/1.0.0.md`. Новый файл начинается с копии [`TEMPLATE.md`](TEMPLATE.md).

Скрипт релиза (`scripts/release.sh`, MD-23) берёт этот файл дважды:
- для окна обновления Sparkle — через `generate_appcast`;
- для описания релиза на GitHub.

Поэтому пишем для пользователя, а не для разработчика.

## Правила

- **Язык — английский.** Приложение по умолчанию английское, окно Sparkle показывает один файл.
- **Разделы — только из шаблона: New, Changed, Fixed.** Пустой раздел удаляется. Заголовок с номером версии не нужен: версию показывают и Sparkle, и GitHub.
- **Один пункт — одно изменение, одной строкой.**
  - Пункт описывает, что изменилось для пользователя, а не что поменяли в коде.
  - Сочетание клавиш — в тексте пункта, если оно есть.
  - Без ID задач, имён файлов и внутренних терминов.
- **«Changed» обязателен**, если что-то работает не так, как раньше. В пункте — что делать пользователю.
- **Тон рабочего инструмента**, как и на сайте (`docs/site-copy.md`): без «улучшили опыт» и восклицательных знаков.

## Пример

```markdown
## New

- Export to PDF with ⌘E.
- Checklists: click a checkbox in the text view to check it off.

## Changed

- Switching between the text and Markdown views is now ⌘/ instead of ⌘⇧M.

## Fixed

- The cursor no longer jumps to the end of the document after undo.
```
