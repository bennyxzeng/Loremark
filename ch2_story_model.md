# Story model：86—EIGHTY-SIX, Vol. 1 · revision 2

> 引用匹配通过只表示该短引用逐字出现在所标段落中，**不代表引用支持对应结论**。每条主张仍需人工阅读原文判断。这是逐节自动抽取并累计的结果，不是事实真相。

## 覆盖范围

- 修订 2（`b35d4891b1f5`），创建于 2026-11-01T23:00:43Z，来源运行 `86v1-ch2`
- 已处理 2 节（按阅读顺序）：
  - `section-004`（Chapter 1）Chapter 1: A Battlefield with Zero Casualties · revision 1 · 185 段
  - `section-005`（Chapter 2）Chapter 2: All Quiet on the Skeletal Front · revision 2 · 285 段
- 起点：`section-004`。之前未处理的节：`section-001`、`section-002`、`section-003`。本模型不包含这些节的信息，不代表“全书开头到当前”的完整状态。
- ⚠️ revision 1、2 的增量含 3 处人工修正（只改证据位置），不是模型原样输出：
  - revision 1 `f000123` `new_records.relationships[18].evidence[1].quote`：“To my darling Theobald” → ‘To my darling Theobald’（p0172 has single curly quotes around the card text; the model returned double quotes）
  - revision 2 `f000243` `new_records.events[7].evidence[0].paragraph_id`：p0116 → p0115（The quote occurs verbatim in p0115, the neighboring paragraph）
  - revision 2 `f000248` `new_records.events[12].evidence[0].paragraph_id`：p0207 → p0208（The quote occurs verbatim in p0208, the neighboring paragraph）
- 统计：实体 43（人物 24、地点 11、组织 8）；有效记录 253 / 共 255；状态转换 2

## 身份

### 推断或转述的身份链接（未合并）

- `f000156` `c007` Lena’s late father ＝ `c008` Václav · `inferred`：Karlstahl says Lena takes after Václav in the same conversation about her late father, suggesting Václav is her father’s name.
  - 证据：[section-004:p0125] “You really do take after Václav…”

## 人物（24）

### `c001` Vladilena Milizé

- 名称：Vladilena Milizé — [section-004:p0027] “Major Vladilena Milizé, commanding control officer for the eastern front’s ninth ward, third defensive squadron.”
- 别名：
  - Lena — [section-004:p0007] “A young boy passed by Lena”
  - Handler One — [section-004:p0032] “Handler One to Pleiades—Resonance complete.”
- 属性：
  - **age**：sixteen · `explicit` — [section-004:p0008] “The sixteen-year-old girl”
  - **ethnicity**：Alba · `explicit` — [section-004:p0008] “not only an Alba”
  - **lineage**：pureblood Celena · `explicit` — [section-004:p0008] “but also a pureblood Celena”
  - **rank**：Major · `explicit` — [section-004:p0027] “Major Vladilena Milizé”
  - **occupation**：Handler · `explicit` — [section-004:p0059] “part of her role as Handler”
  - **affiliation**：Republic military · `explicit` — [section-004:p0008] “the Republic military’s dark-blue collared uniform for female officers”
  - **appearance**：silver hair and silver eyes · `explicit` — [section-004:p0008] “Her softly flowing, silken hair and long eyelashes were a striking silver, and her large, equally silver eyes”
  - **role**：commanding officer of the eastern front’s first ward’s first defensive squadron (Spearhead squadron) · `explicit` — [section-004:p0125] “I hereby appoint you to the role of commanding officer for the eastern front’s first ward’s first defensive squadron”
  - **former\_role**：commanding control officer for the eastern front’s ninth ward, third defensive squadron · `explicit` — [section-004:p0027] “commanding control officer for the eastern front’s ninth ward, third defensive squadron”
  - **voice**：like a clear silver bell · `explicit` — [section-005:p0041] “her voice like a clear silver bell”
  - **tenure**：appointed Handler of the Spearhead squadron a week ago · `explicit` — [section-005:p0236] “Ever since her appointment a week ago”

### `c002` Henrietta Penrose

- 名称：Henrietta Penrose — [section-004:p0021] “certified genius Technical Lieutenant Henrietta Penrose popped up.”
- 别名：
  - Annette — [section-004:p0019] “she turned to find Annette”
- 属性：
  - **rank**：Technical Lieutenant · `explicit` — [section-004:p0019] “She was a technical lieutenant affiliated with the lab division”
  - **occupation**：officer in charge of the Para-RAID development team · `explicit` — [section-004:p0127] “Annette was the officer in charge of the Para-RAID development team”
  - **affiliation**：Republic military · `explicit` — [section-004:p0019] “who had joined the army the same year she had”
  - **age**：same age as Lena · `explicit` — [section-004:p0019] “she was currently Lena’s only friend who was the same age”
  - **skill**：certified genius · `explicit` — [section-004:p0021] “certified genius Technical Lieutenant Henrietta Penrose”
  - **family\_status**：Penrose family, formerly a noble house · `explicit` — [section-004:p0165] “daughter of the Penrose family, formerly a noble house”
  - **ethnicity**：Alba · `inferred` — [section-004:p0022] “Her short hair was an Alba’s silver”

### `c003` Lena’s mother

- 名称：Lena’s mother — [section-004:p0068] “Lena’s mother opened her perfectly rouged lips to speak.”
- 属性：
  - **family\_status**：Milizé household, formerly nobility · `explicit` — [section-004:p0073] “the Milizé household was still considered nobility”
  - **views**：Colorata and the Eighty-Six are filthy animals and should be treated as livestock · `explicit` — [section-004:p0088] “You should know to treat livestock as livestock.”

### `c004` Karlstahl

- 名称：Karlstahl — [section-004:p0091] “Commodore Karlstahl.”
- 别名：
  - Commodore Karlstahl — [section-004:p0091] “Commodore Karlstahl”
  - Uncle Jérôme — [section-004:p0102] ““I-I’m sorry, Uncle Jérôme.””
- 属性：
  - **rank**：Commodore · `explicit` — [section-004:p0091] “Commodore Karlstahl”
  - **role**：division commander · `explicit` — [section-004:p0091] “division commander seated behind the antiquated desk”
  - **appearance**：scarred cheeks, bearded, tall and broad-shouldered · `explicit` — [section-004:p0096] “Karlstahl’s scarred cheeks slackened into a smile. His beard gave off a feeling of gentle dignity, and his frame was tall and broad-shouldered.”

### `c005` Pleiades’s Processor

- 名称：Pleiades’s Processor — [section-004:p0053] “Pleiades’s Processor—the Eighty-Six pilot”
- 别名：
  - third squadron’s captain — [section-004:p0031] “the third squadron’s captain”
- 属性：
  - **status**：Eighty-Six · `explicit` — [section-004:p0053] “the Eighty-Six pilot who agreed to serve on the field of battle for five years”
  - **role**：Processor · `explicit` — [section-004:p0031] “the Processor operating Personal Name unit Pleiades”
  - **unit**：Personal Name unit Pleiades · `explicit` — [section-004:p0031] “Personal Name unit Pleiades”
  - **gender**：male · `explicit` — [section-004:p0032] “the “voice” of a young man”
  - **age**：presumably a year or two older than Lena · `explicit` — [section-004:p0032] “presumably a year or two older than she was”
  - **service\_term**：five years in exchange for restoration of his family’s civil rights · `explicit` — [section-004:p0053] “agreed to serve on the field of battle for five years in exchange for the restoration of his family’s civil rights”

### `c006` Shinei Nouzen

- 名称：Shinei Nouzen — [section-005:p0012] “Shin! Shinei Nouzen!”
- 别名：
  - the Reaper — [section-004:p0107] “call him the Reaper”
  - Spearhead squadron’s captain — [section-004:p0180] “This is the Spearhead squadron’s captain”
  - Shin — [section-005:p0012] “Shin! Shinei Nouzen!”
  - Undertaker — [section-005:p0013] “Don’t you ‘What’s up?’ me, Undertaker!”
- 属性：
  - **status**：Eighty-Six · `explicit` — [section-004:p0174] “The Eighty-Six who drove people to suicide”
  - **role**：Spearhead squadron’s captain · `explicit` — [section-004:p0180] “This is the Spearhead squadron’s captain”
  - **personal\_name\_unit**：Undertaker · `explicit` — [section-004:p0106] “Personal Name: Undertaker”
  - **reputation**：Handlers call him the Reaper and fear him; he has a tendency to break his Handlers · `reported` · 来源 `c004` Karlstahl — [section-004:p0107] “The Handlers who know him seem to call him the Reaper and are all frightened of him… It seems he has a tendency to…break his Handlers.”
  - **voice**：serene as a deep forest lake · `explicit` — [section-004:p0181] “his voice was as serene as a deep forest lake”
  - **age**：about to turn sixteen · `explicit` — [section-005:p0013] “Shin, who was about to turn sixteen this year”
  - **ethnicity**：half-Aquila, half-Rubela · `explicit` — [section-005:p0005] “half-Aquila, half-Rubela blood”
  - **eyes**：Pyrope’s bloodred · `explicit` — [section-005:p0005] “Pyrope’s bloodred eyes”
  - **hair**：Onyx’s jet-black · `explicit` — [section-005:p0005] “Onyx’s jet-black hair”
  - **appearance**：slender build and pale features characteristic of old Empire nobility · `explicit` — [section-005:p0006] “his slender build and pale features were characteristic of the old Empire’s nobility”
  - **rank**：captain · `explicit` — [section-005:p0130] “the rank insignia on his shoulders that marked him as a captain”
  - **combat\_experience**：five years · `explicit` — [section-005:p0278] “Undertaker’s been here the longest. Five years.”
  - **personal\_mark**：headless skeleton carrying a shovel · `explicit` — [section-005:p0020] “a headless skeleton carrying a shovel”
  - **hobby**：reading · `explicit` — [section-005:p0259] “Your hobby is reading, after all.”
  - **combat\_ability**：able to destroy multiple Tank-class Legion in a Juggernaut · `explicit` — [section-005:p0209] “The second Tank type collapsed, and Shin pumped another shell into its vulnerable turret.”
  - **service\_status**：has almost completed his five-year service · `explicit` — [section-005:p0280] “you’ve almost completed your service, Undertaker”

### `c007` Lena’s late father

- 名称：Lena’s late father — [section-004:p0102] “Karlstahl had been best friends with Lena’s late father”
- 属性：
  - **status**：deceased · `explicit` — [section-004:p0074] “I know your late father was a soldier”
  - **occupation**：soldier · `explicit` — [section-004:p0074] “your late father was a soldier”
  - **war\_record**：fought nine years ago in the Republic Armed Forces and was among its sole survivors with Karlstahl · `explicit` — [section-004:p0102] “who had fought alongside him nine years ago as part of the now demolished Republic Armed Forces. The two were among its sole survivors.”
  - **views**：objected to the Eighty-Six’s internment until the very end · `explicit` — [section-004:p0086] “who’d greatly objected to the Eighty-Six’s internment until the very end”

### `c008` Václav

- 名称：Václav — [section-004:p0125] “You really do take after Václav…”

### `c009` Josef von Penrose

- 名称：Josef von Penrose — [section-004:p0159] “Professor Josef von Penrose”
- 别名：
  - Professor Josef von Penrose — [section-004:p0159] “Professor Josef von Penrose”
- 属性：
  - **occupation**：professor/researcher · `explicit` — [section-004:p0159] “Professor Josef von Penrose”
  - **status**：deceased · `explicit` — [section-004:p0159] “ultimately killed him”
  - **cause\_of\_death**：accident during an experiment that drove him mad and killed him · `explicit` — [section-004:p0159] “was involved in an accident during an experiment that drove him mad and ultimately killed him”
  - **project**：Sensory Resonance theory and the RAID Device · `explicit` — [section-004:p0159] “shortly after the completion of the Sensory Resonance theory and the RAID Device”

### `c010` the other researcher

- 名称：the other researcher — [section-004:p0157] “The other researcher was an Eighty-Six.”
- 属性：
  - **status**：Eighty-Six · `explicit` — [section-004:p0157] “The other researcher was an Eighty-Six.”
  - **research\_contribution**：fundamental theory and hypothesis for Para-RAID · `inferred` — [section-004:p0156] “The fundamental theory and hypothesis were all the work of other researchers.”
  - **identifier**：name not recorded; Eighty-Six received a number as sole identifier · `explicit` — [section-004:p0157] “The Eighty-Six, who were considered subhuman, didn’t have their names recorded.”

### `c011` Theobald

- 名称：Theobald — [section-004:p0172] “To my darling Theobald”
- 属性：
  - **relationship\_status**：has a mistress and rents an apartment with her · `explicit` — [section-004:p0172] “the apartment he’s renting with his mistress”

### `c012` Saint Magnolia

- 名称：Saint Magnolia — [section-004:p0006] “Saint Magnolia”
- 属性：
  - **role**：patron saint of the revolution · `explicit` — [section-004:p0065] “Saint Magnolia, patron saint of the revolution”

### `c013` Lev Aldrecht

- 首次出现于 revision 2
- 名称：Lev Aldrecht — [section-005:p0013] “Lev Aldrecht, the Spearhead squadron’s maintenance division captain.”
- 属性：
  - **occupation**：maintenance division captain · `explicit` — [section-005:p0013] “the Spearhead squadron’s maintenance division captain”
  - **age**：fifty-something · `explicit` — [section-005:p0013] “a fifty-something-year-old member of the maintenance crew”
  - **appearance**：grizzled graying-ash hair, sunglasses, oil-stained work clothes · `explicit` — [section-005:p0013] “His hair was a grizzled graying-ash color, and he wore sunglasses and oil-stained work clothes.”
  - **war\_record**：survivor who served in the war nine years ago · `explicit` — [section-005:p0013] “being a survivor who’d served in the war nine years ago”

### `c014` Kujo

- 首次出现于 revision 2
- 名称：Kujo — [section-005:p0003] “Kujo had jotted this message down the day he joined the squadron”
- 属性：
  - **status**：deceased · `explicit` — [section-005:p0004] “Kujo’d died ten days ago”
  - **cause\_of\_death**：killed by a self-propelled mine · `explicit` — [section-005:p0023] “One had latched onto Kujo, who’d mistaken it for an injured soldier.”

### `c015` Kino

- 首次出现于 revision 2
- 名称：Kino — [section-005:p0008] “Fellow squad member Kino”
- 别名：
  - Fafnir — [section-005:p0177] “Fafnir (Kino), give me a hand.”

### `c016` Theo

- 首次出现于 revision 2
- 名称：Theo — [section-005:p0046] “Theo, whose hobby was drawing”
- 别名：
  - Laughing Fox — [section-005:p0175] “Laughing Fox (Theo) here.”
- 属性：
  - **age**：turning sixteen this year · `explicit` — [section-005:p0046] “despite turning sixteen this year”
  - **appearance**：Jade’s golden hair and emerald eyes; small, slender stature · `explicit` — [section-005:p0046] “He had a Jade’s golden hair and emerald eyes and, despite turning sixteen this year, had a small, slender stature.”
  - **hobby**：drawing · `explicit` — [section-005:p0046] “Theo, whose hobby was drawing”

### `c017` Haruto

- 首次出现于 revision 2
- 名称：Haruto — [section-005:p0046] “Haruto, who was a Rubis”
- 别名：
  - Falke — [section-005:p0176] “Falke (Haruto).”
- 属性：
  - **ethnicity**：Rubis · `explicit` — [section-005:p0046] “Haruto, who was a Rubis”

### `c018` Raiden

- 首次出现于 revision 2
- 名称：Raiden — [section-005:p0093] “the squadron’s vice captain, Raiden”
- 别名：
  - Wehrwolf — [section-005:p0275] “Wehrwolf’s (Raiden’s) unit”
- 属性：
  - **role**：vice captain · `explicit` — [section-005:p0093] “the squadron’s vice captain, Raiden”
  - **appearance**：reddish-black hair, pureblood Eisen heritage, wild sharp features · `explicit` — [section-005:p0094] “his reddish-black hair, evidence of his pureblood Eisen heritage”
  - **combat\_experience**：fought alongside Shin for three years as his vice captain · `explicit` — [section-005:p0215] “For three years, Raiden had served as Shin’s vice captain”

### `c019` Kaie Taniya

- 首次出现于 revision 2
- 名称：Kaie Taniya — [section-005:p0224] “Kaie Taniya, rising to the challenge!”
- 别名：
  - Kaie — [section-005:p0059] “What are you doing, Kaie?”
- 属性：
  - **gender**：female · `explicit` — [section-005:p0061] “was unmistakably still a girl”
  - **ethnicity**：Orienta · `explicit` — [section-005:p0061] “the black-haired, black-eyed, petite Orienta”
  - **appearance**：black-haired, black-eyed, petite, long ponytail · `explicit` — [section-005:p0061] “Her ponytail, long enough to look like it could fit on the back of a knight’s helmet”

### `c020` Kurena

- 首次出现于 revision 2
- 名称：Kurena — [section-005:p0059] “Kurena stopped the game of tag”
- 别名：
  - Gunslinger — [section-005:p0185] “Gunslinger (Kurena), four units in direction 030, distance 1200.”
- 属性：
  - **gender**：female · `explicit` — [section-005:p0059] “She had short-bobbed, chestnut-colored Agate hair and catlike Topaz eyes.”
  - **appearance**：short-bobbed chestnut-colored Agate hair and catlike Topaz eyes · `explicit` — [section-005:p0059] “She had short-bobbed, chestnut-colored Agate hair and catlike Topaz eyes.”

### `c021` Anju

- 首次出现于 revision 2
- 名称：Anju — [section-005:p0063] “Anju, who had been rinsing her long silvery-blue hair until now”
- 别名：
  - Snow Witch — [section-005:p0174] “Snow Witch (Anju)”
- 属性：
  - **gender**：female · `explicit` — [section-005:p0063] “Anju, who had been rinsing her long silvery-blue hair until now”
  - **ethnicity**：thick Adularia blood with pale-blue Celesta eyes · `explicit` — [section-005:p0063] “she had thick Adularia blood, but her pale-blue Celesta eyes were inherited”
  - **appearance**：long silvery-blue hair · `explicit` — [section-005:p0063] “her long silvery-blue hair”

### `c022` Daiya

- 首次出现于 revision 2
- 名称：Daiya — [section-005:p0075] “their squad mate Daiya popped out of it”
- 别名：
  - Black Dog — [section-005:p0174] “Black Dog (Daiya)”
- 属性：
  - **gender**：male · `explicit` — [section-005:p0076] “He was also, incidentally, a boy.”
  - **ethnicity**：Sapphira · `explicit` — [section-005:p0075] “as was typical of the Sapphira”
  - **appearance**：blond hair and blue eyes · `explicit` — [section-005:p0075] “Daiya had blond hair and blue eyes”

### `c023` Chise

- 首次出现于 revision 2
- 名称：Chise — [section-005:p0120] “Chise, Kuroto.”

### `c024` Kuroto

- 首次出现于 revision 2
- 名称：Kuroto — [section-005:p0120] “Chise, Kuroto.”

## 地点（11）

### `l001` Liberté et Égalité

- 名称：Liberté et Égalité — [section-004:p0004] “capital, Liberté et Égalité”
- 属性：
  - **status**：capital of the Republic of San Magnolia · `explicit` — [section-004:p0004] “the Republic of San Magnolia’s capital, Liberté et Égalité”

### `l002` Palace Blancneige

- 名称：Palace Blancneige — [section-004:p0014] “One corner of Palace Blancneige”
- 属性：
  - **role**：military headquarters · `explicit` — [section-004:p0014] “now served as the military’s luxurious headquarters”

### `l003` Gran Mule

- 名称：Gran Mule — [section-004:p0014] “the Gran Mule”
- 属性：
  - **role**：fortification wall encircling the administrative Sector and center of command · `explicit` — [section-004:p0014] “the fortification wall that encircled the administrative Sector, the Gran Mule”

### `l004` Eighty-Sixth Sector

- 名称：Eighty-Sixth Sector — [section-004:p0038] “The Eighty-Sixth Sector was designated a no-man’s-land”
- 属性：
  - **status**：no-man’s-land populated by Colorata · `explicit` — [section-004:p0038] “The Eighty-Sixth Sector was designated a no-man’s-land, populated by pigs in human form.”

### `l005` First Sector

- 名称：First Sector — [section-004:p0144] “The Republic’s current administrative center was the First Sector”
- 属性：
  - **role**：administrative center of the Republic · `explicit` — [section-004:p0144] “The Republic’s current administrative center was the First Sector”

### `l006` eastern front’s first ward

- 名称：eastern front’s first ward — [section-004:p0099] “the eastern front’s first ward’s first defensive squadron”
- 属性：
  - **role**：important defensive position where the Legion’s advance is fiercest · `explicit` — [section-004:p0100] “it was an imperative defensive position where the Legion’s advance was the fiercest”

### `l007` eastern front’s ninth ward

- 名称：eastern front’s ninth ward — [section-004:p0027] “the eastern front’s ninth ward, third defensive squadron”
- 属性：
  - **role**：area commanded by Lena’s third defensive squadron · `explicit` — [section-004:p0027] “commanding control officer for the eastern front’s ninth ward, third defensive squadron”

### `l008` seventeenth ward

- 名称：seventeenth ward — [section-004:p0003] “the seventeenth ward today”
- 属性：
  - **invasion**：invaded by the Legion · `explicit` — [section-004:p0003] “have invaded the seventeenth ward today”
  - **future\_status**：to be abolished; all forces stationed there dissolved and discharged · `explicit` — [section-004:p0066] “the seventeenth ward of the southern front will be abolished, and all forces stationed there dissolved and discharged”

### `l009` weatherworn barracks

- 首次出现于 revision 2
- 名称：weatherworn barracks — [section-005:p0003] “In the back of the weatherworn barracks’ hangar”

### `l010` riverbank

- 首次出现于 revision 2
- 名称：riverbank — [section-005:p0053] “their washhouse was on the riverbank”

### `l011` ruins of a nameless city

- 首次出现于 revision 2
- 名称：ruins of a nameless city — [section-005:p0093] “They frequented the ruins of some nameless city when scavenging”

## 组织（8）

### `g001` Republic of San Magnolia

- 名称：Republic of San Magnolia — [section-004:p0003] “the Republic of San Magnolia”
- 别名：
  - Republic — [section-004:p0011] “The Republic prided itself on being the first modern democracy in the world”
- 属性：
  - **government\_type**：first modern democracy in the world · `explicit` — [section-004:p0011] “The Republic prided itself on being the first modern democracy in the world”
  - **war\_status**：at war for the past nine years · `explicit` — [section-004:p0004] “the country had been at war for the past nine years”

### `g002` Republic Armed Forces

- 名称：Republic Armed Forces — [section-004:p0041] “the Republic Armed Forces were decimated”
- 别名：
  - Republic military — [section-004:p0015] “not a single soldier in the Republic military”
- 属性：
  - **status**：decimated within half a month nine years earlier; now demolished · `explicit` — [section-004:p0041] “the Republic Armed Forces were decimated within half a month”

### `g003` Empire of Giad

- 名称：Empire of Giad — [section-004:p0040] “the Empire of Giad”
- 属性：
  - **status**：superpower of the northern continent that declared war on its neighbors · `explicit` — [section-004:p0040] “superpower of the northern continent, the Empire of Giad, declared war on all its neighboring countries”
  - **history**：fell into ruin four years ago · `explicit` — [section-004:p0121] “it seemed to have fallen into ruin four years ago”

### `g004` Legion

- 名称：Legion — [section-004:p0040] “combat drone, Legion”
- 属性：
  - **nature**：army of autonomous unmanned combat drones · `explicit` — [section-004:p0040] “army of the world’s first completely autonomous unmanned combat drone, Legion”
  - **lifespan**：central processors have a fixed lifespan; all units expected to shut down in two years · `explicit` — [section-004:p0146] “all Legion units would shut down. That was a fact the Republic discerned by inspecting several Legion units they’d seized. The Legion’s central processors had a fixed life span programmed into them”
  - **unit\_types**：Ameise, Grauwolf, Löwe, Skorpion, Eintagsfliege · `explicit` — [section-005:p0157] “Scout-type Ameise”；[section-005:p0159] “Dragoon-type Grauwolf”；[section-005:p0160] “Tank-type Löwe”；[section-005:p0181] “Long-Range Gunner-type Skorpion”；[section-005:p0161] “Electronic Disruption types—the Eintagsfliege”

### `g005` Spearhead squadron

- 名称：Spearhead squadron — [section-004:p0099] “also known as the Spearhead squadron”
- 别名：
  - eastern front’s first ward’s first defensive squadron — [section-004:p0099] “the eastern front’s first ward’s first defensive squadron”
- 属性：
  - **role**：elite unit of veterans; first ward’s first defensive squadron · `explicit` — [section-004:p0099] “the eastern front’s first ward’s first defensive squadron, also known as the Spearhead squadron. It’s a unit that consists of veterans”
  - **composition**：all members are Name Bearers with four to six years of combat experience · `explicit` — [section-005:p0154] “All members of the Spearhead squadron were distinguished Name Bearers with four to six years of combat experience”
  - **deployed\_units**：twenty-one Juggernauts · `explicit` — [section-005:p0132] “twenty-one armored weapon systems awakened”

### `g006` third defensive squadron

- 名称：third defensive squadron — [section-004:p0027] “third defensive squadron”
- 属性：
  - **size**：twenty-four units · `explicit` — [section-004:p0028] “The third squadron, which was under Lena’s command, had twenty-four units”

### `g007` Republic Military Industries (RMI)

- 名称：Republic Military Industries (RMI) — [section-004:p0049] “manufactured by Republic Military Industries (RMI)”
- 属性：
  - **role**：manufacturer of the Juggernaut · `explicit` — [section-004:p0049] “manufactured by Republic Military Industries (RMI)”

### `g008` Spearhead squadron’s maintenance division

- 首次出现于 revision 2
- 名称：Spearhead squadron’s maintenance division — [section-005:p0013] “the Spearhead squadron’s maintenance division captain”
- 属性：
  - **role**：maintains the Spearhead squadron’s Juggernauts · `explicit` — [section-005:p0031] “Makin’ sure you kids come back alive is the maintenance team’s job.”

## 关系（有效 31）

- `f000105` `c001` Vladilena Milizé —member\_of→ `g002` Republic Armed Forces · `explicit` · `current`
  - Lena serves in the Republic military. — [section-004:p0008] “She was clad in the Republic military’s dark-blue collared uniform for female officers.”
- `f000106` `c002` Henrietta Penrose —member\_of→ `g002` Republic Armed Forces · `explicit` · `current`
  - Annette is a technical lieutenant in the Republic military. — [section-004:p0019] “She was a technical lieutenant affiliated with the lab division”
- `f000107` `c004` Karlstahl —member\_of→ `g002` Republic Armed Forces · `explicit` · `current`
  - Karlstahl is a Commodore in the Republic military. — [section-004:p0091] “Commodore Karlstahl”
- `f000108` `c005` Pleiades’s Processor —member\_of→ `g006` third defensive squadron · `explicit` · `current`
  - Pleiades’s Processor is the captain of the third defensive squadron. — [section-004:p0031] “the third squadron’s captain, the Processor operating Personal Name unit Pleiades”
- `f000109` `c006` Shinei Nouzen —member\_of→ `g005` Spearhead squadron · `explicit` · `current`
  - Undertaker is the captain of the Spearhead squadron. — [section-004:p0180] “This is the Spearhead squadron’s captain, Personal Name: Undertaker”
- `f000110` `g005` Spearhead squadron —part\_of→ `g002` Republic Armed Forces · `explicit` · `current`
  - The Spearhead squadron is a unit of the Republic military. — [section-004:p0099] “It’s the eastern front’s first ward’s first defensive squadron, also known as the Spearhead squadron.”
- `f000111` `g006` third defensive squadron —part\_of→ `g002` Republic Armed Forces · `explicit` · `current`
  - The third defensive squadron is a unit of the Republic military. — [section-004:p0027] “commanding control officer for the eastern front’s ninth ward, third defensive squadron”
- `f000112` `g004` Legion —part\_of→ `g003` Empire of Giad · `explicit` · `current`
  - The Legion is the Empire of Giad’s autonomous drone army. — [section-004:p0040] “the Empire of Giad, declared war on all its neighboring countries and began attacking with an army of the world’s first completely autonomous unmanned combat drone, Legion”
- `f000113` `g003` Empire of Giad —at\_war\_with→ `g001` Republic of San Magnolia · `explicit` · `current`
  - The Empire of Giad declared war on its neighboring countries, including the Republic of San Magnolia. — [section-004:p0040] “declared war on all its neighboring countries”
- `f000114` `g001` Republic of San Magnolia —at\_war\_with→ `g004` Legion · `explicit` · `current`
  - The Republic of San Magnolia is at war with the Legion. — [section-004:p0003] “A group of the unmanned Imperial weapons known as the Legion have invaded the seventeenth ward today.”
- `f000115` `c001` Vladilena Milizé —commands→ `c005` Pleiades’s Processor · `explicit` · `current`
  - Lena serves as Handler One, commanding the third squadron and its captain, Pleiades’s Processor. — [section-004:p0031] “Lena linked her consciousness with the third squadron’s captain”
- `f000116` `c001` Vladilena Milizé —commands→ `c006` Shinei Nouzen · `explicit` · `current`
  - Lena is appointed Handler of the Spearhead squadron, whose captain is Undertaker. — [section-004:p0180] “This is the Spearhead squadron’s captain, Personal Name: Undertaker”
- `f000117` `c002` Henrietta Penrose —friend\_of→ `c001` Vladilena Milizé · `explicit` · `current`
  - Annette has been Lena’s friend since secondary school and is her only same-age friend. — [section-004:p0019] “a friend of Lena’s since secondary school. As they had both skipped a grade, she was currently Lena’s only friend who was the same age.”
- `f000118` `c009` Josef von Penrose —father\_of→ `c002` Henrietta Penrose · `explicit` · `current`
  - Josef von Penrose is Annette’s father. — [section-004:p0159] “Annette’s father, Professor Josef von Penrose”
- `f000119` `c004` Karlstahl —best\_friends\_with→ `c007` Lena’s late father · `explicit` · `past`
  - Karlstahl was best friends with Lena’s late father. — [section-004:p0102] “Karlstahl had been best friends with Lena’s late father”
- `f000120` `c004` Karlstahl —honorary\_uncle\_of→ `c001` Vladilena Milizé · `explicit` · `current`
  - Lena calls Karlstahl Uncle Jérôme; he visited her when she was small and supported her family after her father’s death. — [section-004:p0102] ““I-I’m sorry, Uncle Jérôme.””；[section-004:p0102] “after her father’s passing, he helped arrange the funeral, as well as support Lena and her family in various ways”
- `f000121` `c007` Lena’s late father —father\_of→ `c001` Vladilena Milizé · `explicit` · `past`
  - Lena’s late father was her father. — [section-004:p0074] “I know your late father was a soldier”
- `f000122` `c003` Lena’s mother —mother\_of→ `c001` Vladilena Milizé · `explicit` · `current`
  - Lena’s mother is her mother. — [section-004:p0068] “Lena’s mother”
- `f000123` `c011` Theobald —arranged\_marriage\_with→ `c002` Henrietta Penrose · `inferred` · `current`
  - Theobald is the man who came for Annette’s arranged marriage meeting. — [section-004:p0169] “the guy who came over for my arranged marriage test them”；[section-004:p0172] “‘To my darling Theobald’”
- `f000124` `l001` Liberté et Égalité —capital\_of→ `g001` Republic of San Magnolia · `explicit` · `current`
  - Liberté et Égalité is the capital of the Republic of San Magnolia. — [section-004:p0004] “the Republic of San Magnolia’s capital, Liberté et Égalité”
- `f000225` `c014` Kujo —member\_of→ `g005` Spearhead squadron · `explicit` · `past`
  - Kujo was a member of the Spearhead squadron. — [section-005:p0003] “the day he joined the squadron”
- `f000226` `c015` Kino —member\_of→ `g005` Spearhead squadron · `explicit` · `current`
  - Kino is a member of the Spearhead squadron. — [section-005:p0008] “Fellow squad member Kino”
- `f000227` `c016` Theo —member\_of→ `g005` Spearhead squadron · `explicit` · `current`
  - Theo is a member of the Spearhead squadron. — [section-005:p0046] “his squad mate’s joke”
- `f000228` `c017` Haruto —member\_of→ `g005` Spearhead squadron · `explicit` · `current`
  - Haruto is a member of the Spearhead squadron. — [section-005:p0046] “his squad mate’s joke”
- `f000229` `c018` Raiden —member\_of→ `g005` Spearhead squadron · `explicit` · `current`
  - Raiden is the vice captain of the Spearhead squadron. — [section-005:p0093] “the squadron’s vice captain, Raiden”
- `f000230` `c022` Daiya —member\_of→ `g005` Spearhead squadron · `explicit` · `current`
  - Daiya is a member of the Spearhead squadron. — [section-005:p0075] “their squad mate Daiya”
- `f000231` `c013` Lev Aldrecht —commands→ `g008` Spearhead squadron’s maintenance division · `explicit` · `current`
  - Lev Aldrecht is captain of the Spearhead squadron’s maintenance division. — [section-005:p0013] “the Spearhead squadron’s maintenance division captain”
- `f000232` `g008` Spearhead squadron’s maintenance division —part\_of→ `g005` Spearhead squadron · `explicit` · `current`
  - The maintenance division is part of the Spearhead squadron. — [section-005:p0013] “the Spearhead squadron’s maintenance division captain”
- `f000233` `c006` Shinei Nouzen —commands→ `g005` Spearhead squadron · `explicit` · `current`
  - Shin is the captain of the Spearhead squadron. — [section-005:p0131] “cold red eyes of this squad captain”
- `f000234` `c018` Raiden —subordinate\_of→ `c006` Shinei Nouzen · `explicit` · `current`
  - Raiden has served as Shin’s vice captain for three years. — [section-005:p0215] “For three years, Raiden had served as Shin’s vice captain”
- `f000235` `c001` Vladilena Milizé —commands→ `g005` Spearhead squadron · `explicit` · `current`
  - Lena acts as Handler One for the Spearhead squadron’s units. — [section-005:p0146] “Handler One to all units.”

## 事件（有效 45，按章节顺序，再按章内叙述顺序）

### `section-004` Chapter 1: A Battlefield with Zero Casualties

1. `f000125` A news broadcast reports that the Legion invaded the seventeenth ward and was repelled by the Juggernauts with no Republic casualties. · `explicit` · `current`
   - 参与者：`g004` Legion，`g001` Republic of San Magnolia；地点：`l008` seventeenth ward；时间：—
   - 证据：[section-004:p0003] “A group of the unmanned Imperial weapons known as the Legion have invaded the seventeenth ward today.”
2. `f000126` Lena walks through the capital, observes the peaceful Alba citizens, and watches the news broadcast with a darkening expression. · `explicit` · `current`
   - 参与者：`c001` Vladilena Milizé；地点：`l001` Liberté et Égalité；时间：—
   - 证据：[section-004:p0010] “Lena’s expression darkened at the sight of the snowy-haired, silver-eyed alabaster newscaster’s brilliant smile.”
3. `f000127` Drunk Republic officers mock Lena as a doll-loving princess; Annette arrives and greets her. · `explicit` · `current`
   - 参与者：`c001` Vladilena Milizé，`c002` Henrietta Penrose；地点：`l001` Liberté et Égalité；时间：—
   - 证据：[section-004:p0017] “our little doll-loving princess has something to say”；[section-004:p0019] “she turned to find Annette”
4. `f000128` Annette tells Lena her information terminal alert is on; Lena heads to her command room. · `explicit` · `current`
   - 参与者：`c001` Vladilena Milizé，`c002` Henrietta Penrose；地点：`l002` Palace Blancneige；时间：—
   - 证据：[section-004:p0023] “The alert on your information terminal was on.”；[section-004:p0025] “made her way to her designated command room”
5. `f000129` Lena authenticates as Major Vladilena Milizé and activates the Para-RAID. · `explicit` · `current`
   - 参与者：`c001` Vladilena Milizé；地点：`l002` Palace Blancneige；时间：—
   - 证据：[section-004:p0027] “Commence authentication. Major Vladilena Milizé”；[section-004:p0029] “Activate Para-RAID.”
6. `f000130` Lena resonates with Pleiades’s Processor, who greets her with bitter irony as an Eighty-Six. · `explicit` · `current`
   - 参与者：`c001` Vladilena Milizé，`c005` Pleiades’s Processor；地点：`l002` Palace Blancneige；时间：—
   - 证据：[section-004:p0037] “Your polite greetings to us subhuman Eighty-Six are much appreciated, Alba.”
7. `f000131` Nine years earlier, the Empire of Giad declared war on its neighbors and attacked with the Legion. · `explicit` · `past`
   - 参与者：`g003` Empire of Giad，`g004` Legion；地点：—；时间：nine years earlier, year 358 of the Republic calendar, year 2136 of the global calendar
   - 证据：[section-004:p0040] “the Empire of Giad, declared war on all its neighboring countries and began attacking with an army of the world’s first completely autonomous unmanned combat drone, Legion”
8. `f000132` The Republic Armed Forces were decimated within half a month; the Republic government evacuated citizens to the eighty-fifth Sector and issued Presidential Order #6609. · `explicit` · `past`
   - 参与者：`g002` Republic Armed Forces，`g001` Republic of San Magnolia；地点：—；时间：nine years earlier
   - 证据：[section-004:p0042] “The first was the evacuation of all the Republic’s citizens to the eighty-fifth administrative Sector. The second was Presidential Order #6609.”
9. `f000133` Colorata opposition to the law was silenced; racial propaganda spread and Colorata were banished to internment camps and forced labor. · `explicit` · `past`
   - 参与者：`g001` Republic of San Magnolia；地点：—；时间：nine years earlier
   - 证据：[section-004:p0046] “Thus, all Colorata in the Republic were banished to internment camps where they were forced into labor”
10. `f000134` Two years later, the Republic introduced the Juggernaut, piloted by Eighty-Six designated as Processors. · `explicit` · `past`
   - 参与者：`g001` Republic of San Magnolia，`g007` Republic Military Industries (RMI)；地点：—；时间：two years later
   - 证据：[section-004:p0049] “The Eighty-Six who served as pilots were designated information-processing units— Processors—making the Juggernaut an Operated Drone.”
11. `f000135` The Legion retreats; Lena’s third squadron loses seven Juggernauts and all seven Processors. · `explicit` · `current`
   - 参与者：`c001` Vladilena Milizé，`c005` Pleiades’s Processor，`g006` third defensive squadron，`g004` Legion；地点：`l007` eastern front’s ninth ward；时间：—
   - 证据：[section-004:p0051] “her third squadron lost seven units. A bitter taste filled her mouth. Seven Juggernauts detonated, exploding along with the Processors who piloted them. None survived.”
12. `f000136` Lena reports the enemy retreat and offers condolences for the seven lost; Pleiades’s Processor replies with cold contempt. · `explicit` · `current`
   - 参与者：`c001` Vladilena Milizé，`c005` Pleiades’s Processor；地点：`l002` Palace Blancneige；时间：—
   - 证据：[section-004:p0058] “Hope you enjoyed watching us pigs squabble through your little telescope, Handler One.”
13. `f000137` The next morning’s news reports no casualties and announces the seventeenth ward will be abolished and its forces discharged. · `explicit` · `current`
   - 参与者：`g001` Republic of San Magnolia；地点：`l008` seventeenth ward；时间：—
   - 证据：[section-004:p0066] “the seventeenth ward of the southern front will be abolished, and all forces stationed there dissolved and discharged”
14. `f000138` At breakfast, Lena’s mother urges her to quit the army and find a groom and calls the Eighty-Six filthy animals; Lena defends them as Republic citizens. · `explicit` · `current`
   - 参与者：`c001` Vladilena Milizé，`c003` Lena’s mother；地点：—；时间：—
   - 证据：[section-004:p0076] “They’re respectable citizens of the Republic, same as you and me.”
15. `f000139` Lena remembers a quadruped spider with a headless skeletal knight crest and a hand that saved her, colored brilliant red and jet-black. · `explicit` · `past`
   - 参与者：`c001` Vladilena Milizé；地点：—；时间：—
   - 证据：[section-004:p0086] “that silhouette of a quadruped spider, the crest of a headless skeletal knight etched upon its armor, the extended hand that had saved her from disaster”
16. `f000140` Lena’s mother insists the Eighty-Six are barbarians to be confined; Lena finishes breakfast and leaves. · `explicit` · `current`
   - 参与者：`c001` Vladilena Milizé，`c003` Lena’s mother；地点：—；时间：—
   - 证据：[section-004:p0088] “You simply cannot get those barbarian Eighty-Six to understand human ideals and nobility.”
17. `f000141` Commodore Karlstahl informs Lena that another squadron’s Handler resigned and she is to become Handler of the Spearhead squadron. · `explicit` · `current`
   - 参与者：`c004` Karlstahl，`c001` Vladilena Milizé，`g005` Spearhead squadron；地点：`l002` Palace Blancneige；时间：—
   - 证据：[section-004:p0099] “It’s the eastern front’s first ward’s first defensive squadron, also known as the Spearhead squadron.”
18. `f000142` Karlstahl warns Lena that Undertaker, called the Reaper, has a history of breaking his Handlers and that some former Handlers committed suicide. · `reported` · `current` · 来源 `c004` Karlstahl
   - 参与者：`c004` Karlstahl，`c001` Vladilena Milizé，`c006` Shinei Nouzen；地点：`l002` Palace Blancneige；时间：—
   - 证据：[section-004:p0107] “The Handlers who know him seem to call him the Reaper and are all frightened of him… It seems he has a tendency to…break his Handlers.”
19. `f000143` Lena accepts command of the Spearhead squadron. · `explicit` · `current`
   - 参与者：`c001` Vladilena Milizé，`c004` Karlstahl，`g005` Spearhead squadron；地点：`l002` Palace Blancneige；时间：—
   - 证据：[section-004:p0114] “I’ll do it. I’ll put all my efforts into serving as the Spearhead squadron’s commanding officer.”
20. `f000144` Karlstahl tells Lena to stop recording casualties; Lena protests that there is no basis for confining the Colorata. · `explicit` · `current`
   - 参与者：`c004` Karlstahl，`c001` Vladilena Milizé；地点：`l002` Palace Blancneige；时间：—
   - 证据：[section-004:p0120] “There’s no basis for confining the Colorata anymore.”
21. `f000145` The Empire of Giad is said to have fallen into ruin four years ago, after its transmissions ceased. · `explicit` · `past`
   - 参与者：`g003` Empire of Giad；地点：—；时间：four years ago
   - 证据：[section-004:p0121] “it seemed to have fallen into ruin four years ago”
22. `f000146` Karlstahl says the Empire’s fall removes the justification for internment but civilians resist change; Lena says tolerating wrongs is supporting them. · `explicit` · `current`
   - 参与者：`c004` Karlstahl，`c001` Vladilena Milizé；地点：`l002` Palace Blancneige；时间：—
   - 证据：[section-004:p0123] “Being tolerant of such wrongs is tantamount to supporting them.”
23. `f000147` Karlstahl officially appoints Lena as commanding officer of the eastern front’s first ward’s first defensive squadron. · `explicit` · `current`
   - 参与者：`c004` Karlstahl，`c001` Vladilena Milizé，`g005` Spearhead squadron；地点：`l002` Palace Blancneige；时间：—
   - 证据：[section-004:p0125] “I hereby appoint you to the role of commanding officer for the eastern front’s first ward’s first defensive squadron”
24. `f000148` Annette tells Lena that some former Handlers did commit suicide, including one who shot himself, and mentions Undertaker. · `explicit` · `current`
   - 参与者：`c002` Henrietta Penrose，`c001` Vladilena Milizé，`c006` Shinei Nouzen；地点：—；时间：—
   - 证据：[section-004:p0132] “One blew his own head off with a shotgun.”
25. `f000149` Annette reveals that Para-RAID came from Esper research, involved an Eighty-Six researcher, and warns of sensory overload; she recalls her father’s fatal experiment accident. · `explicit` · `current`
   - 参与者：`c002` Henrietta Penrose，`c001` Vladilena Milizé，`c009` Josef von Penrose，`c010` the other researcher；地点：—；时间：—
   - 证据：[section-004:p0159] “Annette’s father, Professor Josef von Penrose, was involved in an accident during an experiment that drove him mad and ultimately killed him.”
26. `f000150` Annette offers Lena chiffon cake; she says her arranged-marriage candidate tested it and that she left a chocolate message for Theobald at his mistress’s apartment. · `explicit` · `current`
   - 参与者：`c002` Henrietta Penrose，`c001` Vladilena Milizé，`c011` Theobald；地点：—；时间：—
   - 证据：[section-004:p0172] “Left it in the mailbox of the apartment he’s renting with his mistress.”
27. `f000151` Lena returns home, activates the Para-RAID, and introduces herself to the Spearhead squadron as Handler One. · `explicit` · `current`
   - 参与者：`c001` Vladilena Milizé，`g005` Spearhead squadron；地点：—；时间：—
   - 证据：[section-004:p0177] “Handler One to all units in the Spearhead squadron. It’s a pleasure to meet you all.”
28. `f000152` Undertaker responds as the Spearhead squadron’s captain; Lena affirms that the Eighty-Six are human beings. · `explicit` · `current`
   - 参与者：`c006` Shinei Nouzen，`c001` Vladilena Milizé；地点：—；时间：—
   - 证据：[section-004:p0180] “This is the Spearhead squadron’s captain, Personal Name: Undertaker, speaking.”；[section-004:p0184] “They were human beings. They were not something subhuman, something known only as an Eighty-Six.”

### `section-005` Chapter 2: All Quiet on the Skeletal Front

1. `f000236` Shin sees the interrupted countdown message in the barracks hangar and reflects that Kujo died ten days ago. · `explicit` · `current`
   - 参与者：`c006` Shinei Nouzen，`c014` Kujo；地点：`l009` weatherworn barracks；时间：—
   - 证据：[section-005:p0004] “But Kujo’d died ten days ago.”
2. `f000237` Lev Aldrecht scolds Shin for repeatedly wrecking his Juggernaut and says repairs must wait for restocking. · `explicit` · `current`
   - 参与者：`c006` Shinei Nouzen，`c013` Lev Aldrecht；地点：`l009` weatherworn barracks；时间：—
   - 证据：[section-005:p0014] “Why d’ya gotta wreck your unit every friggin’ time ya sortie?!”
3. `f000238` Aldrecht and Shin discuss Kujo’s death by a self-propelled mine and the squadron’s comparatively easy life. · `explicit` · `current`
   - 参与者：`c006` Shinei Nouzen，`c013` Lev Aldrecht，`c014` Kujo；地点：`l009` weatherworn barracks；时间：—
   - 证据：[section-005:p0023] “I hear Kujo got blown to bits.”
4. `f000239` Shin tells Aldrecht that his new Handler increased paperwork and that he has been faking patrol reports. · `explicit` · `current`
   - 参与者：`c006` Shinei Nouzen，`c013` Lev Aldrecht；地点：`l009` weatherworn barracks；时间：—
   - 证据：[section-005:p0037] “My paperwork’s increased. I guess I’ll have to start faking my patrol reports every day now.”
5. `f000240` In the barracks kitchen, Haruto brings a boar while Theo cooks berry jam, and they discuss the barbecue and laundry duty. · `explicit` · `current`
   - 参与者：`c017` Haruto，`c016` Theo；地点：`l009` weatherworn barracks；时间：—
   - 证据：[section-005:p0046] “They were in the barracks’ kitchen.”
6. `f000241` At the riverbank, Kurena and the female squad members play in the water; Daiya appears, is pelted, and delivers a message from Shin. · `explicit` · `current`
   - 参与者：`c020` Kurena，`c019` Kaie Taniya，`c021` Anju，`c022` Daiya；地点：`l010` riverbank；时间：—
   - 证据：[section-005:p0075] “their squad mate Daiya popped out of it”；[section-005:p0082] “I started working as a messenger today.”
7. `f000242` Raiden tests Fido on food versus trash in city ruins; Fido finds a dead Republic soldier beneath a sakura tree, and Raiden pays his respects. · `explicit` · `current`
   - 参与者：`c018` Raiden；地点：`l011` ruins of a nameless city；时间：—
   - 证据：[section-005:p0106] “Raiden spotted a discolored, crumbling skeletal corpse”
8. `f000243` Theo contacts Raiden by Para-RAID to warn of an Eintagsfliege shower and advancing Legion; Raiden orders the hunting party to regroup. · `explicit` · `current`
   - 参与者：`c016` Theo，`c018` Raiden，`c023` Chise，`c024` Kuroto；地点：`l011` ruins of a nameless city；时间：—
   - 证据：[section-005:p0115] “Change of forecast. There’s a shower coming.”
9. `f000244` Shin briefs the Spearhead squadron, and twenty-one Juggernauts deploy for an ambush in the city ruins. · `explicit` · `current`
   - 参与者：`c006` Shinei Nouzen，`g005` Spearhead squadron；地点：`l011` ruins of a nameless city；时间：—
   - 证据：[section-005:p0132] “twenty-one armored weapon systems awakened”
10. `f000245` Lena as Handler One contacts the squadron late; Shin reports that they have already deployed at point 204. · `explicit` · `current`
   - 参与者：`c001` Vladilena Milizé，`c006` Shinei Nouzen；地点：`l011` ruins of a nameless city；时间：—
   - 证据：[section-005:p0146] “Handler One to all units. I’m sorry for being late—I got delayed.”；[section-005:p0149] “We’ve already deployed at point 204.”
11. `f000246` Legion forces including Ameise, Grauwolf, Löwe, and Eintagsfliege enter the kill zone; Shin orders the squadron to open fire. · `explicit` · `current`
   - 参与者：`g004` Legion，`c006` Shinei Nouzen；地点：`l011` ruins of a nameless city；时间：—
   - 证据：[section-005:p0162] “The Ameise platoon entered the kill zone.”；[section-005:p0163] “Open fire.”
12. `f000247` Lena transmits the Long-Range Observer Units’ coordinates, and Shin orders Kurena to snipe them. · `explicit` · `current`
   - 参与者：`c001` Vladilena Milizé，`c006` Shinei Nouzen，`c020` Kurena；地点：`l011` ruins of a nameless city；时间：—
   - 证据：[section-005:p0183] “Transmitting the Long-Range Observer Units’ coordinates right now.”；[section-005:p0185] “Gunslinger (Kurena), four units in direction 030, distance 1200.”
13. `f000248` After restocking from Fido, Shin in Undertaker destroys multiple Löwe tanks in close combat. · `explicit` · `current`
   - 参与者：`c006` Shinei Nouzen，`g004` Legion；地点：`l011` ruins of a nameless city；时间：—
   - 证据：[section-005:p0208] “Undertaker fired.”
14. `f000249` The remaining Legion retreats under Skorpion bombardment, ending the battle. · `explicit` · `current`
   - 参与者：`g004` Legion，`g005` Spearhead squadron；地点：`l011` ruins of a nameless city；时间：—
   - 证据：[section-005:p0218] “The remaining Legion began retreating”
15. `f000250` In the evening, the squadron holds a sharpshooting tournament with Fido while Anju watches. · `explicit` · `current`
   - 参与者：`c017` Haruto，`c015` Kino，`c019` Kaie Taniya，`c018` Raiden，`c020` Kurena，`c006` Shinei Nouzen，`c021` Anju，`c022` Daiya，`c016` Theo；地点：`l009` weatherworn barracks；时间：—
   - 证据：[section-005:p0219] “holding a sharpshooting tournament in front of the hangar”
16. `f000251` The squadron eats a lavish boar dinner; Anju serves Shin coffee, and Shin says focusing on his book makes the voices less loud. · `explicit` · `current`
   - 参与者：`c021` Anju，`c006` Shinei Nouzen；地点：`l009` weatherworn barracks；时间：—
   - 证据：[section-005:p0234] “Focusing on something makes it so I don’t hear it as loudly.”
17. `f000252` Handler One calls after dinner; she complains about Shin’s fake reports, demands handwritten reports, and asks about life after discharge. · `explicit` · `current`
   - 参与者：`c001` Vladilena Milizé，`c006` Shinei Nouzen，`c018` Raiden，`c019` Kaie Taniya，`c022` Daiya；地点：`l009` weatherworn barracks；时间：—
   - 证据：[section-005:p0245] “You sending me the wrong ones wasn’t a mistake.”；[section-005:p0264] “Please send me reports on all your patrols so far, okay?”

## 疑点

### 未解答（6）

- `f000153` Who was the red-and-black armored figure who saved Lena in her memory?（相关：`c001` Vladilena Milizé）
  - 证据：[section-004:p0086] “the extended hand that had saved her from disaster, those shades of brilliant red and jet-black he’d borne since birth”
- `f000154` Whether Undertaker is responsible for the Handlers’ suicides or whether they were haunted by ghosts.（相关：`c006` Shinei Nouzen）
  - 证据：[section-004:p0111] “they claimed they could ‘hear the ghosts’ voices’ and were haunted by them even after retiring from service”
- `f000155` Who is the other Para-RAID researcher, and where were they sent?（相关：`c010` the other researcher）
  - 证据：[section-004:p0157] “At this point, there was no way of even knowing which internment camp they’d been sent to.”
- `f000253` Who was the person from Shin’s past who read him the Bible passage?（相关：`c006` Shinei Nouzen）
  - 证据：[section-005:p0139] “The last time he’d seen and heard that person was painted over in his memories”
- `f000254` Whom is Shin searching for on the battlefield when he thinks “you won’t come out this time”?（相关：`c006` Shinei Nouzen）
  - 证据：[section-005:p0172] “Ah, you won’t come out this time, either, will you?”
- `f000255` Does Kurena actually harbor romantic feelings for Shin, despite her denials?（相关：`c020` Kurena，`c006` Shinei Nouzen）
  - 证据：[section-005:p0072] “I don’t feel anything for Shin”

### 已解答（0）


## 修订历史（2 条状态转换）

- `t000001` revision 2 · `section-005` · **supersede**（替代）
  - 旧：`f000006` 名称 “Undertaker”（`c006` Shinei Nouzen）
  - 新：`f000157` 名称 “Shinei Nouzen”（`c006` Shinei Nouzen）
    - 新记录证据：[section-005:p0012] “Shin! Shinei Nouzen!”
  - 理由：The new section gives Shin’s full personal name, Shinei Nouzen, while Undertaker remains a Personal Name/alias.
  - 本节证据：[section-005:p0012] “Shin! Shinei Nouzen!”
- `t000002` revision 2 · `section-005` · **supersede**（替代）
  - 旧：`f000072` `c006` Shinei Nouzen **age**：a boy roughly Lena’s age · `explicit`
  - 新：`f000184` `c006` Shinei Nouzen **age**：about to turn sixteen · `explicit`
    - 新记录证据：[section-005:p0013] “Shin, who was about to turn sixteen this year”
  - 理由：The new section specifies Shin’s age more precisely as about to turn sixteen this year.
  - 本节证据：[section-005:p0013] “Shin, who was about to turn sixteen this year”
