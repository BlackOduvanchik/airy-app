//
//  SFSymbolsCatalog.swift
//  Airy
//
//  Curated SF Symbol names by category for category icons. Single source of truth for Icon Library and quick pick.
//

import Foundation

enum SFSymbolsCatalog {
    static let alphabet: [String] = [
        "letter:A", "letter:B", "letter:C", "letter:D", "letter:E", "letter:F",
        "letter:G", "letter:H", "letter:I", "letter:J", "letter:K", "letter:L",
        "letter:M", "letter:N", "letter:O", "letter:P", "letter:Q", "letter:R",
        "letter:S", "letter:T", "letter:U", "letter:V", "letter:W", "letter:X",
        "letter:Y", "letter:Z",
    ]

    /// Returns true if the symbol is a letter (from the Alphabet category).
    static func isLetter(_ symbol: String) -> Bool {
        symbol.hasPrefix("letter:")
    }

    /// Extracts the display letter from a "letter:X" symbol.
    static func letterValue(_ symbol: String) -> String {
        String(symbol.dropFirst(7))
    }

    static let finance: [String] = [
        "creditcard.fill", "creditcard", "dollarsign", "dollarsign.circle.fill", "dollarsign.square.fill",
        "centsign", "yensign.circle.fill", "eurosign.circle.fill", "banknote.fill", "banknote",
        "chart.line.uptrend.xyaxis", "chart.bar.fill", "chart.pie.fill", "chart.xyaxis.line",
        "briefcase.fill", "briefcase", "shield.fill", "shield", "doc.text.fill", "doc.richtext.fill",
        "tray.full.fill", "archivebox.fill", "building.columns.fill", "building.2.fill",
        "percent", "number", "sum", "equal.circle.fill", "dollarsign.circle",
        "creditcard.and.123", "chart.bar.doc.horizontal.fill",
    ]

    static let food: [String] = [
        "cart.fill", "cart", "bag.fill", "bag", "basket.fill", "basket",
        "fork.knife", "fork.knife.circle.fill", "cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill",
        "birthday.cake.fill", "leaf.fill", "leaf", "carrot.fill", "apple.logo",
        "wineglass.fill", "mug.fill",
        "fish.fill", "birthday.cake", "frying.pan.fill", "refrigerator.fill",
        "cup.and.saucer", "mug", "wineglass", "carrot", "leaf.circle.fill",
    ]

    static let transport: [String] = [
        "car.fill", "car", "bus.fill", "bus", "tram.fill", "tram",
        "bicycle", "airplane", "airplane.departure", "airplane.arrival",
        "ferry.fill", "fuelpump.fill", "fuelpump", "location.fill", "location",
        "map.fill", "map", "mappin.circle.fill", "mappin.and.ellipse",
        "figure.walk", "figure.run", "figure.roll", "scooter",
        "parkingsign", "road.lanes", "signpost.right.fill", "car.side",
    ]

    static let lifestyle: [String] = [
        "heart.fill", "heart", "star.fill", "star", "flag.fill", "flag",
        "book.fill", "book", "gamecontroller.fill", "gamecontroller",
        "sportscourt.fill", "figure.walk", "gift.fill", "gift",
        "theatermasks.fill", "paintbrush.fill", "paintbrush", "paintpalette.fill",
        "camera.fill", "camera", "photo.fill", "photo", "film.fill", "film",
        "music.note", "music.quarternote.3", "guitars.fill", "piano.keys.inverse",
        "face.smiling.fill", "sparkles", "wand.and.stars", "party.popper.fill",
    ]

    static let home: [String] = [
        "house.fill", "house", "building.2.fill", "building.2", "key.fill", "key",
        "lightbulb.fill", "lightbulb", "fan.fill", "fan", "thermometer.medium",
        "sofa.fill", "bed.double.fill", "washer.fill", "dryer.fill",
        "refrigerator.fill", "oven.fill", "microwave.fill", "dishwasher.fill",
        "lock.fill", "lock.open.fill", "door.garage.closed", "door.garage.open",
        "figure.stand", "armchair.fill", "lamp.floor.fill", "powerplug.fill",
    ]

    static let tech: [String] = [
        "iphone", "iphone.gen3", "laptopcomputer", "desktopcomputer", "tv.fill", "tv",
        "phone.fill", "phone", "envelope.fill", "envelope", "message.fill", "message",
        "wifi", "wifi.circle.fill", "antenna.radiowaves.left.and.right", "bolt.fill", "bolt",
        "gearshape.fill", "gearshape", "square.grid.2x2.fill", "square.grid.2x2",
        "cpu.fill", "cpu", "tag.fill", "tag", "barcode", "qrcode",
        "printer.fill", "scanner.fill", "externaldrive.fill", "internaldrive.fill",
        "display", "macpro.gen3", "airport.extreme.tower", "hifispeaker.fill",
    ]

    static let health: [String] = [
        "heart.fill", "heart.text.square.fill", "cross.case.fill", "cross.vial.fill",
        "pills.fill", "pills", "staroflife.fill", "stethoscope",
        "figure.run", "figure.yoga", "dumbbell.fill", "sportscourt.fill",
        "brain.head.profile", "heart.circle.fill", "waveform.path.ecg",
        "bed.double.fill", "thermometer.medium", "bandage.fill",
    ]

    static let shopping: [String] = [
        "bag.fill", "bag", "cart.fill", "cart", "basket.fill", "creditcard.fill",
        "giftcard.fill", "tag.fill", "tag", "percent", "dollarsign.circle.fill",
        "storefront.fill", "storefront", "building.2.fill", "mappin.circle.fill",
        "handbag.fill", "tshirt.fill", "crown.fill", "sparkles",
    ]

    static let work: [String] = [
        "briefcase.fill", "briefcase", "building.2.fill", "building.2",
        "desktopcomputer", "laptopcomputer", "printer.fill", "doc.fill", "doc.text.fill",
        "folder.fill", "folder", "paperclip", "link", "calendar",
        "clock.fill", "clock", "alarm.fill", "timer", "checkmark.circle.fill",
        "person.fill", "person.2.fill", "person.3.fill", "building.columns.fill",
    ]

    static let nature: [String] = [
        "leaf.fill", "leaf", "tree.fill", "tree", "flower.fill", "camera.macro",
        "sun.max.fill", "moon.fill", "cloud.fill", "cloud.rain.fill",
        "drop.fill", "drop", "flame.fill", "flame", "snowflake",
        "bird.fill", "fish.fill", "pawprint.fill", "ant.fill",
        "ladybug.fill", "tortoise.fill", "hare.fill", "lizard.fill",
    ]

    static let education: [String] = [
        "book.fill", "book", "book.closed.fill", "graduationcap.fill",
        "pencil", "pencil.circle.fill", "highlighter", "paintbrush.fill",
        "ruler.fill", "scissors", "paperclip", "doc.fill",
        "lightbulb.fill", "brain.head.profile", "person.crop.circle.badge.questionmark",
    ]

    static let byCategory: [String: [String]] = [
        "Alphabet": alphabet,
        "Finance": finance,
        "Food": food,
        "Transport": transport,
        "Lifestyle": lifestyle,
        "Home": home,
        "Tech": tech,
        "Health": health,
        "Shopping": shopping,
        "Work": work,
        "Nature": nature,
        "Education": education,
    ]

    static let categoryOrder: [String] = [
        "Alphabet", "Finance", "Food", "Transport", "Lifestyle", "Home", "Tech",
        "Health", "Shopping", "Work", "Nature", "Education",
    ]

    static let allSymbols: [String] = categoryOrder.flatMap { byCategory[$0] ?? [] }
    private static let _allSymbolsSet: Set<String> = Set(allSymbols)
    static func contains(_ symbol: String) -> Bool { _allSymbolsSet.contains(symbol) }

    // MARK: - Localized search keywords

    /// Maps SF Symbol names to space-separated search keywords in all supported languages.
    /// Used to match non-English search queries to symbols.
    static let searchKeywords: [String: String] = [
        // Finance
        "creditcard.fill":        "карта картка картка karte tarjeta cartão carte カード 信用卡 card",
        "creditcard":             "карта картка картка karte tarjeta cartão carte カード 信用卡 card",
        "dollarsign":             "доллар долар долар dollar dólar ドル 美元 деньги гроші грошы money dinero argent geld お金 钱",
        "dollarsign.circle.fill": "доллар долар долар dollar dólar ドル 美元 деньги гроші грошы money",
        "dollarsign.circle":      "доллар долар долар dollar dólar ドル 美元 деньги гроші грошы money",
        "banknote.fill":          "купюра банкнота банкнота банкнота geldschein billete billet nota 紙幣 纸币 cash наличные",
        "banknote":               "купюра банкнота банкнота банкнота geldschein billete billet nota 紙幣 纸币 cash наличные",
        "chart.line.uptrend.xyaxis": "график графік графік diagramm gráfico graphique グラフ 图表 chart trend",
        "chart.bar.fill":         "график графік графік diagramm gráfico graphique グラフ 图表 chart",
        "chart.pie.fill":         "диаграмма діаграма дыяграма diagramm diagrama diagramme 円グラフ 饼图 pie",
        "briefcase.fill":         "портфель портфель партфель koffer maletín mallette ブリーフケース 公文包 work",
        "building.columns.fill":  "банк банк банк bank banco banque 銀行 银行",
        "building.2.fill":        "здание будівля будынак gebäude edificio bâtiment ビル 建筑 office офис",
        "percent":                "процент відсоток працэнт prozent porcentaje pourcentage パーセント 百分比 скидка",
        "shield.fill":            "щит щит щыт schutz escudo bouclier シールド 盾 защита безопасность",

        // Food
        "cart.fill":              "корзина кошик кошык wagen carrito chariot カート 购物车 тележка магазин",
        "cart":                   "корзина кошик кошык wagen carrito chariot カート 购物车 тележка магазин",
        "bag.fill":               "сумка сумка сумка tasche bolsa sac バッグ 包 пакет покупки",
        "bag":                    "сумка сумка сумка tasche bolsa sac バッグ 包 пакет покупки",
        "fork.knife":             "еда їжа ежа essen comida nourriture 食事 餐 ресторан вилка нож",
        "fork.knife.circle.fill": "еда їжа ежа essen comida nourriture 食事 餐 ресторан",
        "cup.and.saucer.fill":    "кофе кава кава kaffee café コーヒー 咖啡 чай tea tee чашка",
        "cup.and.saucer":         "кофе кава кава kaffee café コーヒー 咖啡 чай tea tee чашка",
        "birthday.cake.fill":     "торт торт торт kuchen pastel gâteau ケーキ 蛋糕 cake день рождения",
        "leaf.fill":              "лист листок ліст blatt hoja feuille 葉 叶 природа эко веган",
        "carrot.fill":            "морковь морква морква karotte zanahoria carotte にんじん 胡萝卜 овощи",
        "wineglass.fill":         "вино вино віно wein vino vin ワイン 葡萄酒 бокал алкоголь",
        "mug.fill":               "кружка кружка кубак becher taza mug マグカップ 杯子 чай кофе",
        "fish.fill":              "рыба риба рыба fisch pescado poisson 魚 鱼 seafood",
        "frying.pan.fill":        "сковорода сковорода патэльня pfanne sartén poêle フライパン 锅 готовка",
        "refrigerator.fill":      "холодильник холодильник халадзільнік kühlschrank refrigerador réfrigérateur 冷蔵庫 冰箱",

        // Transport
        "car.fill":               "машина авто автомобіль аўтамабіль auto coche voiture 車 汽车 car",
        "car":                    "машина авто автомобіль аўтамабіль auto coche voiture 車 汽车 car",
        "bus.fill":               "автобус автобус аўтобус bus autobús バス 公交车",
        "tram.fill":              "трамвай трамвай трамвай straßenbahn tranvía tramway 路面電車 有轨电车",
        "bicycle":                "велосипед велосипед веласіпед fahrrad bicicleta vélo 自転車 自行车 bike",
        "airplane":               "самолёт літак самалёт flugzeug avión avion 飛行機 飞机 flight рейс",
        "airplane.departure":     "самолёт літак самалёт flugzeug avión avion 飛行機 飞机 вылет",
        "airplane.arrival":       "самолёт літак самалёт flugzeug avión avion 飛行機 飞机 прилёт",
        "fuelpump.fill":          "бензин пальне паліва tankstelle gasolina essence ガソリン 加油 заправка топливо",
        "location.fill":          "место місце месца standort ubicación emplacement 場所 位置 геолокация",
        "map.fill":               "карта мапа карта karte mapa carte 地図 地图",
        "figure.walk":            "пешком пішки пешшу gehen caminar marcher 歩く 步行 ходьба прогулка",
        "scooter":                "самокат самокат самакат roller patinete trottinette スクーター 滑板车",
        "parkingsign":            "парковка паркування паркоўка parken aparcamiento parking 駐車 停车",

        // Lifestyle
        "heart.fill":             "сердце серце сэрца herz corazón cœur ハート 心 любовь love здоровье",
        "heart":                  "сердце серце сэрца herz corazón cœur ハート 心 любовь love",
        "star.fill":              "звезда зірка зорка stern estrella étoile 星 星 избранное favorite",
        "star":                   "звезда зірка зорка stern estrella étoile 星 星 избранное",
        "book.fill":              "книга книга кніга buch libro livre 本 书 чтение читать",
        "book":                   "книга книга кніга buch libro livre 本 书 чтение читать",
        "gamecontroller.fill":    "игра гра гульня spiel juego jeu ゲーム 游戏 развлечение",
        "gift.fill":              "подарок подарунок падарунак geschenk regalo cadeau プレゼント 礼物",
        "gift":                   "подарок подарунок падарунак geschenk regalo cadeau プレゼント 礼物",
        "theatermasks.fill":      "театр театр тэатр theater teatro théâtre 劇場 剧院 кино маска",
        "camera.fill":            "камера камера камера kamera cámara caméra カメラ 相机 фото",
        "photo.fill":             "фото фото фота foto foto photo 写真 照片 снимок",
        "film.fill":              "фильм фільм фільм film película film 映画 电影 кино видео",
        "music.note":             "музыка музика музыка musik música musique 音楽 音乐",
        "sparkles":               "блеск блиск бляск glitzer brillo éclat キラキラ 闪耀 красота",
        "party.popper.fill":      "праздник свято свята party fiesta fête パーティー 派对 вечеринка",
        "paintbrush.fill":        "кисть пензель пэндзаль pinsel pincel pinceau 筆 画笔 рисование искусство",
        "paintpalette.fill":      "палитра палітра палітра palette paleta palette パレット 调色板 искусство",

        // Home
        "house.fill":             "дом дім дом haus casa maison 家 房子 home жильё квартира",
        "house":                  "дом дім дом haus casa maison 家 房子 home жильё",
        "key.fill":               "ключ ключ ключ schlüssel llave clé 鍵 钥匙",
        "lightbulb.fill":         "лампа лампа лямпа lampe bombilla ampoule 電球 灯泡 свет идея",
        "sofa.fill":              "диван диван канапа sofa sofá canapé ソファ 沙发 мебель",
        "bed.double.fill":        "кровать ліжко ложак bett cama lit ベッド 床 сон спальня",
        "washer.fill":            "стирка прання пранне waschmaschine lavadora lave-linge 洗濯機 洗衣机",
        "lock.fill":              "замок замок замок schloss cerradura serrure ロック 锁 безопасность",
        "powerplug.fill":         "розетка розетка разетка stecker enchufe prise コンセント 插座 электричество",

        // Tech
        "iphone":                 "телефон телефон тэлефон telefon teléfono téléphone 電話 手机 смартфон",
        "laptopcomputer":         "ноутбук ноутбук наўтбук laptop portátil ordinateur ノートパソコン 笔记本 компьютер",
        "desktopcomputer":        "компьютер комп'ютер камп'ютар computer computadora ordinateur コンピュータ 电脑",
        "tv.fill":                "телевизор телевізор тэлевізар fernseher televisor télévision テレビ 电视",
        "envelope.fill":          "письмо лист ліст brief correo courrier メール 邮件 email почта",
        "message.fill":           "сообщение повідомлення паведамленне nachricht mensaje message メッセージ 消息 чат",
        "wifi":                   "интернет інтернет інтэрнэт internet internet インターネット 网络 вайфай",
        "gearshape.fill":         "настройки налаштування налады einstellungen ajustes paramètres 設定 设置 settings",
        "tag.fill":               "тег тег тэг tag etiqueta étiquette タグ 标签 метка ярлык",
        "printer.fill":           "принтер принтер прынтар drucker impresora imprimante プリンター 打印机",

        // Health
        "cross.case.fill":        "аптечка аптечка аптэчка arztkoffer botiquín trousse 救急箱 急救箱 медицина",
        "pills.fill":             "таблетки таблетки таблеткі pillen pastillas pilules 薬 药 лекарства",
        "stethoscope":            "врач лікар лекар arzt médico médecin 医者 医生 доктор",
        "figure.yoga":            "йога йога ёга yoga yoga yoga ヨガ 瑜伽 фитнес спорт",
        "dumbbell.fill":          "гантели гантелі гантэлі hantel pesas haltère ダンベル 哑铃 спорт тренировка",
        "brain.head.profile":     "мозг мозок мозг gehirn cerebro cerveau 脳 大脑 психология",

        // Shopping
        "giftcard.fill":          "подарочная карта подарункова картка падарункавая картка gutschein tarjeta carte cadeau ギフトカード 礼品卡",
        "storefront.fill":        "магазин магазин крама laden tienda magasin 店 商店 shop",
        "storefront":             "магазин магазин крама laden tienda magasin 店 商店 shop",
        "handbag.fill":           "сумка сумка сумка handtasche bolso sac ハンドバッグ 手提包",
        "tshirt.fill":            "одежда одяг адзенне kleidung ropa vêtements 服 衣服 футболка",
        "crown.fill":             "корона корона карона krone corona couronne 王冠 皇冠 люкс премиум",

        // Work
        "folder.fill":            "папка папка тэчка ordner carpeta dossier フォルダ 文件夹",
        "paperclip":              "скрепка скріпка скрэпка büroklammer clip trombone クリップ 回形针",
        "calendar":               "календарь календар каляндар kalender calendario calendrier カレンダー 日历 дата",
        "clock.fill":             "часы годинник гадзіннік uhr reloj horloge 時計 时钟 время time",
        "alarm.fill":             "будильник будильник будзільнік wecker alarma réveil アラーム 闹钟",
        "checkmark.circle.fill":  "галочка галочка галачка häkchen marca coche チェック 勾选 готово done",
        "person.fill":            "человек людина чалавек person persona personne 人 人 пользователь",
        "person.2.fill":          "люди люди людзі personen personas personnes 人々 人们 команда team",

        // Nature
        "tree.fill":              "дерево дерево дрэва baum árbol arbre 木 树",
        "flower.fill":            "цветок квітка кветка blume flor fleur 花 花",
        "sun.max.fill":           "солнце сонце сонца sonne sol soleil 太陽 太阳 погода",
        "moon.fill":              "луна місяць месяц mond luna lune 月 月亮 ночь",
        "cloud.fill":             "облако хмара воблака wolke nube nuage 雲 云 погода",
        "cloud.rain.fill":        "дождь дощ дождж regen lluvia pluie 雨 雨 погода",
        "drop.fill":              "капля крапля кропля tropfen gota goutte 滴 水滴 вода water",
        "flame.fill":             "огонь вогонь агонь feuer fuego feu 炎 火 пламя",
        "snowflake":              "снежинка сніжинка сняжынка schneeflocke copo de nieve flocon 雪 雪花 зима",
        "pawprint.fill":          "лапа лапа лапа pfote pata patte 肉球 爪印 питомец животное pet",

        // Education
        "graduationcap.fill":     "выпускной випускний выпускны abschluss graduación diplôme 卒業 毕业 учёба",
        "pencil":                 "карандаш олівець аловак bleistift lápiz crayon 鉛筆 铅笔 писать",
        "ruler.fill":             "линейка лінійка лінейка lineal regla règle 定規 尺子",
        "scissors":               "ножницы ножиці нажніцы schere tijeras ciseaux はさみ 剪刀",
    ]

    /// Pre-lowercased keywords for efficient search (avoids repeated `.lowercased()` on every filter pass).
    static let searchKeywordsLowercased: [String: String] = searchKeywords.mapValues { $0.lowercased() }
}
