import Foundation
import Testing
import MarkdownCore

/// Full-document parse time. The editor re-parses on edits, so this bounds
/// typing latency on large files. The limit only catches pathological
/// slowdowns (debug builds are slow); the printed time is the number to
/// track, ideally from `swift test -c release --filter Performance`.
@Suite("Performance")
struct PerformanceTests {
    @Test(arguments: [1, 5])
    func parsesLargeDocuments(megabytes: Int) {
        let document = largeDocument(bytes: megabytes * 1_000_000)
        let clock = ContinuousClock()
        var map: SyntaxMap?
        let duration = clock.measure {
            map = SyntaxMap(parsing: document)
        }
        print("SyntaxMap: \(document.utf8.count) bytes, \(map?.spans.count ?? 0) spans in \(duration)")
        #expect(duration < .seconds(20 * megabytes))
        #expect((map?.spans.count ?? 0) > 0)
    }
}

private func largeDocument(bytes: Int) -> String {
    let chunk = """
    # Заголовок раздела **важный** ##

    Обычный абзац с *курсивом*, **жирным**, ~~зачёркнутым~~ и `кодом`, а ещё
    ссылка на [документацию](https://example.com/docs) и картинка ![схема](img/схема.png).
    Вторая строка того же абзаца с эмодзи 😀 и <span style="color: red">цветом</span>.

    > Цитата с **выделением**
    > и продолжением на второй строке.

    - Пункт списка с *акцентом*
    - [ ] Задача, которую надо сделать
    - [x] Сделанная задача
      1. Вложенный нумерованный пункт
      2. Ещё один пункт с `кодом`

    ```swift
    let greeting = "Привет, мир"
    print(greeting)
    ```

    | Колонка | Значение |
    |---------|:--------:|
    | *один*  | **два**  |

    ---


    """
    let repeats = max(1, bytes / chunk.utf8.count)
    return String(repeating: chunk, count: repeats)
}
