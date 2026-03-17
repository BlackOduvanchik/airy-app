# Полный аудит экранов и попапов Airy

Справочный документ — используй названия/номера для указания на конкретную страницу/попап.

---

## TAB STRUCTURE (3 таба + FAB)

**Файл:** `Airy/Shared/Components/MainTabView.swift`

| Tab | Иконка | Экран по умолчанию |
|-----|--------|-------------------|
| Dashboard | house.fill | DashboardView |
| Insights | chart.line.uptrend.xyaxis | InsightsView |
| Settings | gearshape.fill | SettingsView |
| FAB (центр) | plus | AddActionSheetView (sheet) |

---

## ЭКРАНЫ

### 1. DASHBOARD (главный экран)

**Файл:** `Airy/Features/Dashboard/DashboardView.swift`
**Фон:** OnboardingGradientBackground (голубой/зелёный/бежевый радиальный градиент)

**Элементы:**
- Cloud иконка (48x48, белый радиальный градиент, синяя иконка) — кнопка импорта
- Бейджи статуса на cloud иконке: красный круг (анализирует), зелёная галка (есть неотсмотренные), синий круг (pending review)
- "Total spent this month" подзаголовок (15pt medium, серый)
- Большая сумма (48pt light)
- Дельта бейдж (зелёная галка + процент, белая капсула)
- AI Summary карточка (sparkles иконка, glass panel 28pt radius)
- "CATEGORY BREAKDOWN" секция — сегментированный бар + легенда (tap → CategoryBreakdownView)
- "RECENT ACTIVITY" — список транзакций (44x44 иконки, 14pt имя, 16pt сумма)
- "UPCOMING BILLS" — горизонтальный скролл карточек подписок (110pt width)

**Кнопки:** Glass panel стиль (ultraThinMaterial, white opacity 0.45, 28pt radius, 1pt stroke)

---

### 2. CATEGORY BREAKDOWN (доля по категориям)

**Файл:** `Airy/Features/Dashboard/CategoryBreakdownView.swift`
**Как попасть:** Tap на "CATEGORY BREAKDOWN" в Dashboard
**Заголовок:** Месяц по центру (12pt semibold)

**Элементы:**
- Назад (chevron.left, белый круг 40x40)
- Donut chart (260pt диаметр, 43pt stroke)
- В центре: "Total" + сумма (28pt light)
- Тултип при выборе сегмента (точка + категория + сумма + процент)
- Список категорий (36x36 иконки, прогресс бар, сумма)
- Tap на категорию → CategoryDetailView

---

### 3. CATEGORY DETAIL (транзакции по категории)

**Файл:** `Airy/Features/Dashboard/CategoryDetailView.swift`
**Как попасть:** Tap на категорию в CategoryBreakdownView
**Заголовок:** "Category Details" (12pt semibold)

**Элементы:**
- Категория + общая сумма (32pt light)
- Транзакции по дням (заголовки дней, glass panels)
- Каждая транзакция: иконка (44x44), merchant (15pt semibold), сумма, subcategory badge, note
- Tap → AddTransactionView (edit)

---

### 4. INSIGHTS (аналитика)

**Файл:** `Airy/Features/Insights/InsightsView.swift`
**Заголовок:** "Your Money Mirror" (34pt light) + "INSIGHTS" (12pt semibold tracking 1)

**Элементы:**
- Cloud иконка (48x48)
- AI карточка (sparkles, glass panel)
- Сравнение: "This Month" / "Last Month" (2 плитки, 20pt medium суммы, дельта чип)
- Yearly Overview — линейный чарт с градиентной заливкой (12 месяцев)
- "What Changed" — горизонтальный скролл pills (emoji + категория + дельта %)
- Insight Mirror карточки (sparkles + текст)
- Anomaly карточка (оранжевая полоса слева, треугольник warning)
- Subscription Trend — 6 вертикальных баров

**Фон:** OnboardingGradientBackground

---

### 5. SETTINGS (настройки)

**Файл:** `Airy/Features/Settings/SettingsView.swift`
**Заголовок:** "Your Airy" (40pt light) + "SETTINGS" (12pt semibold)

**Секции:**
- **Pro карточка:** cloud иконка, "Unlock Airy Pro", "View Plans" кнопка (зелёная капсула), градиентный бордер
- **Preferences:** Currency (Menu), Theme (цветные точки), каждая строка 64pt
- **AI Parsing Rules:** sparkles + chevron
- **Data:** Merchant Memory, Export, iCloud Sync toggle (зелёный tint)
- **Notifications:** Monthly Summary toggle, Spending Alerts toggle
- **Privacy:** Face ID toggle, Data Usage, Delete All Data (красная иконка + красный текст)
- **Debug:** Last extraction report, Clear OCR templates
- **Account:** User ID, Sign out

**Стиль секций:** Rounded 28pt, ultraThinMaterial, white overlay, 1pt stroke, shadow

---

### 6. ALL SPENDING (все транзакции)

**Файл:** `Airy/Features/Transactions/TransactionListView.swift`
**Как попасть:** fullScreenCover из Dashboard (cloud иконка или ellipsis)
**Заголовок:** "All Spending" (34pt light) + "TRANSACTIONS" в toolbar

**Элементы:**
- Pinned транзакции (если есть)
- Поиск
- Filter pills (горизонтальный скролл категорий)
- Месяцы — карточки с суммой за месяц
- Tap на месяц → MonthDetailView

---

### 7. MONTH DETAIL (детали месяца)

**Файл:** `Airy/Features/Transactions/MonthDetailView.swift`
**Как попасть:** Navigation push из TransactionListView
**Заголовок:** Месяц (12pt semibold)

**Элементы:**
- "Spent this month" + большая сумма (36pt light)
- "SPENDING CALENDAR" — интерактивный календарь с точками
- Список транзакций (glass panels, tap → edit sheet)
- Clear filter chip (если выбран диапазон дней)
- Tap на календарь → CalendarPickerSheetView (fullScreenCover)

---

### 8. WHAT YOU PAY FOR (подписки)

**Файл:** `Airy/Features/Subscriptions/SubscriptionsView.swift`
**Как попасть:** fullScreenCover из Dashboard ("Upcoming Bills")
**Заголовок:** "What You Pay For" (34pt light)

**Элементы:**
- Cloud иконка (48x48)
- Summary карточка: общая сумма/mo + дельта + мини donut chart (64x64)
- Легенда: топ 2 категории + % от расходов
- Recurring Insights текст
- Список подписок: иконка (36x36), merchant, next billing date, сумма

---

## ПОПАПЫ И SHEETS

### 9. ADD ACTION SHEET (FAB меню)

**Файл:** `Airy/Shared/Components/AddActionSheetView.swift`
**Как попасть:** Tap на FAB (+) в bottom nav
**Высота:** 300pt sheet
**Заголовок:** "ADD TRANSACTION" / "ADD SCREENSHOT"

**Страница 1:**
- Add Expense (красная иконка)
- Add Income (зелёная иконка)
- Add Screenshot (синяя иконка)

**Страница 2 (screenshot):**
- Paste from Clipboard
- Open Gallery

**Кнопки:** white opacity 0.72, 18pt radius, 52pt height

---

### 10. NEW ENTRY / EDIT TRANSACTION

**Файл:** `Airy/Features/Transactions/AddTransactionView.swift`
**Как попасть:** Sheet из разных экранов
**Заголовок:** "New Entry" (или edit mode) + селектор валюты

**Элементы:**
- Сумма (56pt light) — tap открывает кастомную клавиатуру
- Type Toggle: Expense / Income (сегментированный контрол)
- Subscription toggle + Weekly/Monthly/Yearly pills
- Категории: 4-колоночная сетка (32x32 иконки, 18pt radius)
- Выбранная категория: белый фон + зелёный border
- Merchant field, Date picker, Time picker, Note input
- Все поля: white opacity 0.3 фон, 20pt radius
- Delete (красный, только в edit) + Save (тёмный фон, белый текст, 20pt radius)

---

### 11. DATE PICKER POPOVER

**Файл:** `Airy/Features/Transactions/DatePickerPopoverView.swift`
**Как попасть:** Tap на дату в AddTransactionView
**Размер:** 180pt width
**Стиль:** Glass (ultraThinMaterial + white 0.5, 24pt radius)

3 колеса: Month | Day | Year (snap к 32pt строкам)

---

### 12. TIME PICKER POPOVER

**Файл:** `Airy/Features/Transactions/TimePickerPopoverView.swift`
**Как попасть:** Tap на время в AddTransactionView
**Размер:** 140pt width
**Стиль:** То же что Date Picker

2 колеса: Hours (0-23) | Minutes (0-59)

---

### 13. CUSTOM KEYBOARD (калькулятор)

**Файл:** `Airy/Features/Transactions/AmountKeyboardView.swift`
**Как попасть:** Tap на сумму в AddTransactionView
**Стиль:** Снизу, full width, ultraThinMaterial фон, spring анимация

Цифры + операторы (+, -, ×, ÷) + дисплей выражения

---

### 14. CATEGORIES PICKER (полный выбор категорий)

**Файл:** `Airy/Features/Transactions/CategoriesSheetView.swift`
**Как попасть:** Sheet из AddTransactionView (tap "Other")
**Фон:** Светлый sage (RGB 0.956, 0.969, 0.961)
**Заголовок:** "Categories"

**Элементы:**
- Handle bar + "Categories" заголовок (19pt bold)
- "Edit" кнопка (pencil + текст, белый фон, 12pt radius)
- "New" кнопка (plus + текст, тёмный фон, 12pt radius)
- Search bar (белый фон, 20pt radius)
- Список категорий (раскрываемые, с subcategories)

**Edit mode:**
- List с drag handles (.onMove)
- Swipe-to-delete категорий
- Expand → subcategories с minus.circle.fill (удалить) и pencil (редактировать)
- "Add subcategory" кнопка внизу

---

### 15. NEW/EDIT CATEGORY

**Файл:** `Airy/Features/Transactions/NewCategorySheetView.swift`
**Как попасть:** Sheet из CategoriesSheetView
**Заголовок:** "New Category" / "Edit Category"
**Фон:** Sage с ultraThinMaterial

**Элементы:**
- Name input + Short description input (16pt radius, green border on focus)
- Icon grid (6 колонок, 14pt radius, + "more" кнопка → IconLibraryView)
- Parent Category selector (только при создании)
- Color row (16 цветов, 8 колонок)
- Preview card (как будет выглядеть)
- Create/Save кнопка (тёмный фон, 18pt radius)

---

### 16. NEW/EDIT SUB CATEGORY

**Файл:** `Airy/Features/Transactions/NewSubcategorySheetView.swift`
**Как попасть:** Sheet из CategoriesSheetView (edit mode)
**Заголовок:** "New Sub Category" / "Edit Sub Category"
**Стиль:** Тот же что NewCategorySheetView

**Элементы:** Name input + Parent Category selector + Save кнопка
(без иконки, без цвета)

---

### 17. PARENT CATEGORY PICKER

**Файл:** `Airy/Features/Transactions/NewCategorySheetView.swift` (struct ParentCategoryPickerSheet)
**Как попасть:** Sheet из NewCategorySheetView или NewSubcategorySheetView

**Элементы:**
- "Parent Category" заголовок
- "None (top-level)" опция
- Список категорий с иконками и subcategory preview
- Выбранная: белый фон + зелёный checkmark
- "Confirm" кнопка (тёмный фон)

---

### 18. CALENDAR PICKER (выбор дат)

**Файл:** `Airy/Features/Transactions/CalendarPickerSheetView.swift`
**Как попасть:** fullScreenCover из MonthDetailView (tap на календарь)

**Элементы:**
- Полный календарь с выбором range
- Month/Year wheel popup (custom overlay с тёмным фоном)
- Select/Cancel кнопки

---

### 19. GALLERY PICKER

**Файл:** `Airy/Features/Import/GalleryPickerView.swift`
**Как попасть:** fullScreenCover из MainTabView
**Тип:** Системный PHPickerViewController (до 30 фото)

---

### 20. ANALYZING TRANSACTIONS (анализ скриншотов)

**Файл:** `Airy/Features/Import/AnalyzingTransactionsView.swift`
**Как попасть:** fullScreenCover после импорта фото
**Фон:** OnboardingGradientBackground

**Элементы:**
- Превью очереди (3 миниатюры, 60x80pt)
- Cloud иконка с анимацией
- "X of Y" прогресс + ротация статус-фраз
- Список извлечённых транзакций (realtime, staggered animation)
- Confirm/Cancel кнопки

---

### 21. REVIEW TRANSACTIONS (ревью перед сохранением)

**Файл:** `Airy/Features/Import/PendingReviewView.swift`
**Как попасть:** fullScreenCover после анализа
**Заголовок:** "Review Transactions" (24pt bold) + зелёный count badge

**Элементы:**
- Карточки транзакций (merchant, amount, category, date)
- Duplicate/confidence флаги
- Swipe to delete
- Tap → edit (sheet с AddTransactionView)
- "Save All" кнопка (тёмный фон) + Skip

---

### 22. PAYWALL

**Файл:** `Airy/Features/Paywall/PaywallView.swift`
**Как попасть:** Sheet из Settings, Insights, Subscriptions
**Заголовок:** "Airy Pro"

Subscribe + Restore purchases кнопки

---

### 23. AI PARSING RULES

**Файл:** `Airy/Features/Settings/AIParsingRulesSheetView.swift`
**Как попасть:** Sheet из Settings
**Заголовок:** "AI Parsing Rules"

OpenAI API Key + OCR source selector + Generate кнопка

---

## ALERTS

| Где | Заголовок | Сообщение |
|-----|----------|-----------|
| MainTabView | "No image in clipboard" | "Copy an image first, then try again." |
| ExtractionDebugReportListView | "Export failed" | Error message |

## CONFIRMATION DIALOGS

| Где | Заголовок | Действие |
|-----|----------|----------|
| CategoriesSheetView (14) | "Delete Subcategory" | Удаление subcategory (транзакции остаются в родительской категории) |
| SettingsView (5) | "Delete All Data" | Удаление всех данных + sign out |
| SettingsView (5) | "Clear OCR Templates" | Очистка шаблонов извлечения |

---

## ДИЗАЙН-СИСТЕМА

### Цвета (OnboardingDesign)

| Токен | Hex | Использование |
|-------|-----|--------------|
| textPrimary | #1E2D24 | Заголовки, основной текст |
| textSecondary | #5E7A6B | Подписи |
| textTertiary | #8AA396 | Лейблы, caption |
| accentGreen | #67A082 | Успех, позитивные метрики, выбранное |
| accentBlue | #7B9DAB | Действия, инфо, subcategories |
| accentAmber | #D9A05B | Предупреждения |
| textDanger | #D67A7A | Ошибки, удаление |
| glassBg | white @ 45% | Фон панелей |
| glassBorder | white @ 60% | Рамки панелей |
| glassHighlight | white @ 90% | Акцентные рамки |

### Glass Morphism (стандарт для всех панелей)

```
Фон:       .ultraThinMaterial
Overlay:   white.opacity(0.45) at 50%
Radius:    28pt
Stroke:    1pt white.opacity(0.6)
Shadow:    textPrimary.opacity(0.06), radius 16, y: 8
```

### Типографика

| Размер | Вес | Использование |
|--------|-----|--------------|
| 56pt | light | Сумма в AddTransaction (10) |
| 48pt | light | Dashboard total (1) |
| 34-40pt | light | Заголовки экранов (4, 5, 6, 8) |
| 24pt | bold | Review Transactions заголовок (21) |
| 19pt | bold | Sheet заголовки (14, 15, 16) |
| 15-16pt | semibold | Body текст, кнопки |
| 14pt | semibold | Merchant names, interactive elements |
| 13pt | medium | Подписи, subtitles |
| 12pt | semibold | Section labels (UPPERCASE, tracking 0.5) |

### Стандартные радиусы

| Radius | Использование |
|--------|--------------|
| 28pt | Glass panels (стандарт) |
| 24pt | Popovers (11, 12), Action sheet (9) |
| 20pt | Form inputs, кнопки (10) |
| 18pt | Create/Save кнопки (15, 16) |
| 16pt | Input fields (15, 16) |
| 14pt | Subcategory rows, icon grid items |
| 12pt | Маленькие кнопки (Edit/New в 14) |

### Навигация

- Back button: `chevron.left`, 12pt semibold (в MonthDetail, TransactionList)
- Toolbar title: 12pt semibold, tracking 0.5, textPrimary или textTertiary
- `.navigationBarTitleDisplayMode(.inline)` везде
- `.navigationBarBackButtonHidden(true)` + кастомная кнопка назад
