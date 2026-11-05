# Молитва для KOReader / Molytva for KOReader

## Українською

Плагін показує літургійний день УГКЦ і доступні богослужіння. В архіві плагіна є лише невеликий демонстраційний пакет. Тексти богослужінь **не входять до плагіна**: після вашої команди KOReader завантажує їх через Wi-Fi прямо з «Молитви Церкви» ([prayer-service.pp.ua](https://prayer-service.pp.ua), А. Мартинишин) у власний каталог пристрою. Ми не розповсюджуємо ці тексти. Тексти залишаються © їхніх авторів; отримані пакети призначені для особистого користування з дозволу автора. **Комерційне використання текстів заборонено.**

1. Розпакуйте `molytva.koplugin` у `.adds/koreader/plugins/` на Kobo. Перевірте, що існує `.adds/koreader/plugins/molytva.koplugin/main.lua`.
2. Перезапустіть KOReader. У головному меню відкрийте **Молитва → Налаштування**. Виберіть **Новоюліанський — Україна** або **Григоріанський — діаспора**, а також 1–3 місяці наперед (типово 1, тобто поточний і наступний місяць).
3. Підключіть Wi-Fi і натисніть **Молитва → Оновити тексти**. Плагін перевіряє архіви за `If-Modified-Since`, робить паузу між запитами (типово 5 секунд; її можна змінити), збирає пакет на пристрої та показує підсумок. Завантаження починається лише після цієї дії.
4. **Сьогодні** показує доступні служби. Вечірня та Літургія Передшеосвячених Дарів для сьогоднішнього вечора беруться з файлів наступного літургійного дня. **Про пакет** показує дату створення, діапазон, календар і джерело.

Пакет лежить у `<DataStorage:getDataDir()>/molytva/`, кеш архівів — у `molytva-cache/prayer-service.pp.ua/` відносно цього каталогу. Попередній пакет зберігається як `molytva.old/` до наступного успішного оновлення. Якщо місячний архів ще не опубліковано, плагін попереджає і використовує доступні місяці. У грудні архів наступного року може ще не мати календаря. Неповні архіви мають лише ті служби, які вже опубліковані.

**Якщо тексти не з’явилися:** перевірте Wi-Fi і календар у налаштуваннях, повторіть оновлення пізніше, а також перегляньте **Про пакет**. Помилка завантаження чи збирання не замінює чинний пакет. Демонстраційний пакет працює без мережі і на екрані «Сьогодні» нагадує про оновлення. Для старого пакета таке нагадування з’являється через 30 днів після створення.

Десктопний `tools/molytva_pack.py` (з репозиторію) залишається необов’язковим інструментом для особистого офлайн-збирання. Він не потрібен для оновлення на Kobo.

Код плагіна: **AGPL-3.0-only** (`LICENSE`). Ця ліцензія не поширюється на сторонні тексти.

## English

The plugin shows the UGCC liturgical day and available services. The plugin ZIP contains only a small sample pack. Service texts are **not bundled**: when the user chooses **Молитва → Оновити тексти** (Update texts), KOReader downloads archives over Wi-Fi directly from «Молитва Церкви» ([prayer-service.pp.ua](https://prayer-service.pp.ua), A. Martynyshyn). We do not redistribute the texts. They remain © their authors and the resulting pack is for personal use with the author's permission. **Commercial use of the texts is prohibited.**

Install by extracting `molytva.koplugin` into `.adds/koreader/plugins/` and restarting KOReader. Under **Молитва → Налаштування** (Settings), select the New Julian calendar for Ukraine or the Gregorian calendar for the diaspora, then choose 1–3 months ahead. Connect to Wi-Fi and select **Оновити тексти**. Updates are manual, use conditional HTTP requests, and preserve the previous pack if building fails. **Про пакет** (About pack) shows its date, range, calendar, and source.

If texts are missing, check Wi-Fi and calendar selection and retry later; a future monthly archive or calendar may not yet be published. The bundled sample remains usable offline. The Python desktop builder is optional.

Plugin code is **AGPL-3.0-only**. Third party texts retain their own copyright and terms.
