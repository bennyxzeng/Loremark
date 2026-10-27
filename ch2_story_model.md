# Story model：86—EIGHTY-SIX, Vol. 1 · revision 2

> 引用匹配通过只表示该短引用逐字出现在所标段落中，**不代表引用支持对应结论**。每条主张仍需人工阅读原文判断。这是逐节自动抽取并累计的结果，不是事实真相。

## 覆盖范围

- 修订 2（`5ed0861ea7ed`），创建于 2026-10-26T23:52:42Z，来源运行 `20261026T234001Z-299093`
- 已处理 2 节（按阅读顺序）：
  - `section-004`（Chapter 1）Chapter 1: A Battlefield with Zero Casualties · revision 1 · 185 段
  - `section-005`（Chapter 2）Chapter 2: All Quiet on the Skeletal Front · revision 2 · 285 段
- 起点：`section-004`。之前未处理的节：`section-001`、`section-002`、`section-003`。本模型不包含这些节的信息，不代表“全书开头到当前”的完整状态。
- ⚠️ 导入的初始模型含 1 处人工修正，不是模型原样输出（初始运行 `20261026T032410Z-2c6f50`）：
  - `characters[1].attributes[6].evidence[0].paragraph_id`：p0164 → p0163（Quote 'Annette smiled mischievously.' occurs verbatim in p0163, not p0164; only the paragraph ID was changed）
- ⚠️ revision 2 的增量含 10 处人工修正（只改证据位置），不是模型原样输出：
  - revision 2 `f000212` `new_records.names[6].evidence[0].paragraph_id`：p0094 → p0093（Quote occurs verbatim in p0093, not p0094; only the paragraph ID was changed）
  - revision 2 `f000229` `new_records.names[23].evidence[0].quote`：if we ambush near point 304 → if we ambush them near point 304（Quote was not verbatim; replaced with the exact span of p0122 it paraphrased; the cited paragraph was not changed）
  - revision 2 `f000260` `new_records.attributes[18].evidence[0].paragraph_id`：p0094 → p0093（Quote occurs verbatim in p0093, not p0094; only the paragraph ID was changed）
  - revision 2 `f000261` `new_records.attributes[19].evidence[0].paragraph_id`：p0095 → p0094（Quote occurs verbatim in p0094, not p0095; only the paragraph ID was changed）
  - revision 2 `f000261` `new_records.attributes[19].evidence[1].paragraph_id`：p0095 → p0094（Quote occurs verbatim in p0094, not p0095; only the paragraph ID was changed）
  - revision 2 `f000280` `new_records.attributes[38].evidence[1].quote`：the 7.56 mm antipersonnel machine guns on its shoulders → the 7.56 mm antipersonnel machine guns on their shoulders（Quote was not verbatim; replaced with the exact span of p0158 it paraphrased; the cited paragraph was not changed）
  - revision 2 `f000287` `new_records.attributes[45].evidence[0].quote`：if we ambush near point 304 → if we ambush them near point 304（Quote was not verbatim; replaced with the exact span of p0122 it paraphrased; the cited paragraph was not changed）
  - revision 2 `f000295` `new_records.relationships[6].evidence[0].paragraph_id`：p0094 → p0093（Quote occurs verbatim in p0093, not p0094; only the paragraph ID was changed）
  - revision 2 `f000299` `new_records.relationships[10].evidence[0].paragraph_id`：p0059 → p0058（Quote occurs verbatim in p0058, not p0059; only the paragraph ID was changed）
  - revision 2 `f000313` `new_records.events[4].evidence[0].paragraph_id`：p0059 → p0058（Quote occurs verbatim in p0058, not p0059; only the paragraph ID was changed）
- 统计：实体 54（人物 25、地点 15、组织 14）；有效记录 334 / 共 335；状态转换 1

## 人物（25）

### `c001` Lena

- 名称：Lena — [section-004:p0007] “A young boy passed by Lena”
- 别名：
  - Vladilena Milizé — [section-004:p0027] “Major Vladilena Milizé, commanding control officer for the eastern front’s ninth ward, third defensive squadron.”
  - Handler One — [section-004:p0177] “Handler One to all units in the Spearhead squadron.”
- 属性：
  - **age**：16 · `explicit` — [section-004:p0008] “The sixteen-year-old girl”
  - **rank**：Major · `explicit` — [section-004:p0027] “Major Vladilena Milizé”
  - **affiliation**：Republic military · `explicit` — [section-004:p0008] “She was clad in the Republic military’s dark-blue collared uniform for female officers.”
  - **ethnicity**：Alba; pureblood Celena · `explicit` — [section-004:p0008] “not only an Alba, a descendant of the race native to this land since ages past, but also a pureblood Celena”
  - **appearance**：silver hair and silver eyes · `explicit` — [section-004:p0008] “Her softly flowing, silken hair and long eyelashes were a striking silver, and her large, equally silver eyes”
  - **initial command**：commanding control officer for the eastern front’s ninth ward, third defensive squadron · `explicit` — [section-004:p0027] “commanding control officer for the eastern front’s ninth ward, third defensive squadron”
  - **new command**：commanding officer for the eastern front’s first ward’s first defensive squadron · `explicit` — [section-004:p0125] “I hereby appoint you to the role of commanding officer for the eastern front’s first ward’s first defensive squadron”
  - **family**：daughter of the Milizé household · `explicit` — [section-004:p0074] “daughter of the great Milizé household”
  - **father**：late father was a soldier · `explicit` — [section-004:p0074] “I know your late father was a soldier”

### `c002` Annette

- 名称：Annette — [section-004:p0019] “she turned to find Annette”
- 属性：
  - **rank**：Technical lieutenant · `explicit` — [section-004:p0019] “She was a technical lieutenant affiliated with the lab division”
  - **affiliation**：lab division · `explicit` — [section-004:p0019] “She was a technical lieutenant affiliated with the lab division”
  - **friendship**：Lena’s friend since secondary school · `explicit` — [section-004:p0019] “a friend of Lena’s since secondary school”
  - **age**：same age as Lena · `explicit` — [section-004:p0019] “she was currently Lena’s only friend who was the same age”
  - **appearance**：short silver hair and large hanging silver eyes · `explicit` — [section-004:p0022] “Her short hair was an Alba’s silver, and her large, hanging eyes were a similar silvery hue.”
  - **role**：officer in charge of the Para-RAID development team · `explicit` — [section-004:p0127] “Annette was the officer in charge of the Para-RAID development team”
  - **family**：daughter of the Penrose family, formerly a noble house · `inferred` — [section-004:p0163] “Annette smiled mischievously.”；[section-004:p0165] “only the daughter of the Penrose family, formerly a noble house, could afford”
  - **father**：Professor Josef von Penrose · `explicit` — [section-004:p0159] “Annette’s father, Professor Josef von Penrose”

### `c003` Lena’s mother

- 名称：Lena’s mother — [section-004:p0068] “Lena’s mother opened her perfectly rouged lips to speak.”
- 别名：
  - Mother — [section-004:p0076] “Protecting the motherland is a Republic citizen’s duty and pride, Mother.”
- 属性：
  - **appearance**：dressed in an antiquated gown; perfectly rouged lips · `explicit` — [section-004:p0068] “dressed in an antiquated gown, Lena’s mother opened her perfectly rouged lips”
  - **attitude toward Lena's military career**：urges Lena to quit the army and find a groom from a good family · `explicit` — [section-004:p0072] “Lena, isn’t it about time you quit the army and find a groom from a good family?”
  - **prejudice**：calls the Eighty-Six filthy-colored livestock/animals · `explicit` — [section-004:p0077] “when they’re stained with those filthy colors?”；[section-004:p0077] “letting those animals set foot on Republic soil”

### `c004` Karlstahl

- 名称：Karlstahl — [section-004:p0091] “Commodore Karlstahl”
- 别名：
  - Commodore Karlstahl — [section-004:p0091] “Commodore Karlstahl”
  - Uncle Jérôme — [section-004:p0102] “I-I’m sorry, Uncle Jérôme.”
- 属性：
  - **rank**：Commodore · `explicit` — [section-004:p0091] “Commodore Karlstahl”
  - **role**：division commander · `explicit` — [section-004:p0091] “division commander seated behind the antiquated desk”
  - **appearance**：scarred cheeks, beard, tall and broad-shouldered · `explicit` — [section-004:p0096] “Karlstahl’s scarred cheeks slackened into a smile. His beard gave off a feeling of gentle dignity, and his frame was tall and broad-shouldered.”
  - **military history**：fought nine years ago as part of the Republic Armed Forces; one of its sole survivors · `explicit` — [section-004:p0102] “who had fought alongside him nine years ago as part of the now demolished Republic Armed Forces. The two were among its sole survivors.”
  - **support for Lena**：helped arrange her father’s funeral and supported Lena and her family · `explicit` — [section-004:p0102] “he helped arrange the funeral, as well as support Lena and her family in various ways”

### `c005` Pleiades’s Processor

- 名称：Pleiades’s Processor — [section-004:p0053] “Pleiades’s Processor”
- 别名：
  - Pleiades — [section-004:p0033] “Pleiades to Handler One.”
- 属性：
  - **role**：captain of the third squadron and Processor operating Personal Name unit Pleiades · `explicit` — [section-004:p0031] “the third squadron’s captain, the Processor operating Personal Name unit Pleiades”
  - **voice**：young man, presumably a year or two older than Lena · `explicit` — [section-004:p0032] “the “voice” of a young man, presumably a year or two older than she was”
  - **ethnicity/status**：Eighty-Six · `reported` · 来源 `c005` Pleiades’s Processor — [section-004:p0037] “us subhuman Eighty-Six”
  - **service terms**：agreed to serve five years in exchange for restoration of his family’s civil rights · `explicit` — [section-004:p0053] “the Eighty-Six pilot who agreed to serve on the field of battle for five years in exchange for the restoration of his family’s civil rights”
  - **attitude toward Lena**：scathingly ironic · `explicit` — [section-004:p0058] “Hope you enjoyed watching us pigs squabble through your little telescope, Handler One.”
  - **attitude toward Lena**：cold contempt and hatred · `explicit` — [section-004:p0064] “Cold contempt and hatred were sprinkled into those words.”

### `c006` Shinei Nouzen

- 名称：Shinei Nouzen — [section-005:p0012] “Shin! Shinei Nouzen!”；[section-005:p0149] “Undertaker to Handler One.”
- 别名：
  - Reaper — [section-004:p0107] “The Handlers who know him seem to call him the Reaper”
  - Shin — [section-005:p0012] “Shin! Shinei Nouzen!”
  - Undertaker — [section-005:p0149] “Undertaker to Handler One.”
- 属性：
  - **role**：Spearhead squadron’s captain unit · `explicit` — [section-004:p0106] “It’s the Spearhead squadron’s captain unit, Personal Name: Undertaker.”
  - **reputation**：called the Reaper and feared by Handlers · `reported` · 来源 `c004` Karlstahl — [section-004:p0107] “The Handlers who know him seem to call him the Reaper and are all frightened of him”
  - **reputation**：has a tendency to break his Handlers · `reported` · 来源 `c004` Karlstahl — [section-004:p0107] “It seems he has a tendency to…break his Handlers.”
  - **reputation**：many former Handlers requested transfers or resigned; some committed suicide after resigning · `reported` · 来源 `c004` Karlstahl — [section-004:p0110] “an unusually high number of Handlers who were in charge of Undertaker’s squadrons have put in requests to change their assignments or requested to resign from service altogether”；[section-004:p0110] “some have committed suicide after resigning”
  - **voice**：young and serene as a deep forest lake · `explicit` — [section-004:p0181] “his voice was as serene as a deep forest lake”
  - **age/background**：boy roughly Lena’s age, probably originally from a middle-class or higher family · `inferred` — [section-004:p0181] “It was a boy roughly her age, probably originally from a middle-class or higher family.”
  - **ethnicity/status**：Eighty-Six Processor · `inferred` — [section-004:p0049] “The Eighty-Six who served as pilots were designated information-processing units— Processors”；[section-004:p0180] “This is the Spearhead squadron’s captain, Personal Name: Undertaker, speaking.”
  - **demeanor**：detached · `explicit` — [section-004:p0183] “his detached tone”
  - **age**：about to turn sixteen this year · `explicit` — [section-005:p0013] “Shin, who was about to turn sixteen this year”
  - **ethnicity**：noble, mixed, half-Aquila, half-Rubela blood · `explicit` — [section-005:p0005] “These two traits came from his noble, mixed, half-Aquila, half-Rubela blood”
  - **appearance**：calm expression, cold handsome features, slender build, pale features · `explicit` — [section-005:p0006] “His calm expression, unbefitting his age, gave his handsome features a certain cold quality”
  - **clothing**：desert-camouflage uniform with a sky-blue scarf · `explicit` — [section-005:p0007] “he wore a desert-camouflage uniform with shades of sandy brown and gray”；[section-005:p0007] “a sky-blue scarf wrapped around his neck”
  - **rank**：captain · `explicit` — [section-005:p0130] “the rank insignia on his shoulders that marked him as a captain”
  - **personal mark**：headless skeleton carrying a shovel · `explicit` — [section-005:p0020] “Beneath the canopy was his Personal Mark, a headless skeleton carrying a shovel.”
  - **combat role**：vanguard point man exceptionally skilled in close-quarters combat · `explicit` — [section-005:p0171] “he was a point man who was exceptionally skilled in close-quarters combat even among other vanguard”
  - **reports**：has sent the same fabricated report since five years ago · `explicit` — [section-005:p0038] “keep sendin’ the same report ya fabricated five years ago every time”；[section-005:p0245] “they were all the same report.”

### `c007` Professor Josef von Penrose

- 名称：Professor Josef von Penrose — [section-004:p0159] “Professor Josef von Penrose”
- 别名：
  - Annette’s father — [section-004:p0159] “Annette’s father, Professor Josef von Penrose”
- 属性：
  - **occupation**：professor · `explicit` — [section-004:p0159] “Professor Josef von Penrose”
  - **relation**：Annette’s father · `explicit` — [section-004:p0159] “Annette’s father, Professor Josef von Penrose”
  - **Para-RAID research**：collaborative research; prepared lab conditions and replicated the phenomenon with recruited test subjects · `explicit` — [section-004:p0156] “Dad was just in charge of preparing the lab conditions and replicating the phenomenon with the recruited test subjects.”
  - **death**：accident during an experiment drove him mad and ultimately killed him · `explicit` — [section-004:p0159] “was involved in an accident during an experiment that drove him mad and ultimately killed him”
  - **accident detail**：RAID Device synchronization rate was accidently set to the theoretical maximum · `explicit` — [section-004:p0159] “The RAID Device’s synchronization rate was accidently set to the theoretical maximum.”
  - **belief about his accident**：some believed he connected somewhere beyond the human collective unconscious · `reported` — [section-004:p0159] “Some believed he connected to somewhere that lay beyond the human collective unconscious.”

### `c008` Theobald

- 名称：Theobald — [section-004:p0172] “‘To my darling Theobald’”
- 属性：
  - **relation to Annette**：Annette’s arranged-marriage candidate · `inferred` — [section-004:p0169] “the guy who came over for my arranged marriage”；[section-004:p0172] “‘To my darling Theobald’”
  - **personal life**：has a mistress · `explicit` — [section-004:p0172] “apartment he’s renting with his mistress”
  - **reaction to prototype chocolate**：fainted, frothing at the mouth after the fifth prototype chocolate · `explicit` — [section-004:p0170] “he’d fainted, frothing at the mouth after the fifth prototype chocolate”

### `c009` Václav

- 名称：Václav — [section-004:p0125] “You really do take after Václav”
- 属性：
  - **possible relation**：may be Lena’s late father · `inferred` — [section-004:p0102] “best friends with Lena’s late father”；[section-004:p0125] “You really do take after Václav”

### `c010` Saint Magnolia

- 名称：Saint Magnolia — [section-004:p0006] “Saint Magnolia”
- 别名：
  - saint of the revolution — [section-004:p0006] “the saint of the revolution, Saint Magnolia”
  - patron saint of the revolution — [section-004:p0065] “patron saint of the revolution”
- 属性：
  - **role**：saint of the revolution · `explicit` — [section-004:p0006] “the saint of the revolution, Saint Magnolia”
  - **role**：patron saint of the revolution · `explicit` — [section-004:p0065] “patron saint of the revolution”
  - **symbol**：her visage appears on a flag at the city hall · `explicit` — [section-004:p0006] “a flag bearing the visage of the saint of the revolution, Saint Magnolia”

### `c011` newscaster

- 名称：newscaster — [section-004:p0010] “the snowy-haired, silver-eyed alabaster newscaster’s brilliant smile”
- 属性：
  - **appearance**：snowy-haired, silver-eyed Alba · `explicit` — [section-004:p0010] “the snowy-haired, silver-eyed alabaster newscaster”
  - **role**：newscaster on a government-sponsored broadcast · `explicit` — [section-004:p0065] “This was a government-sponsored broadcast”
  - **reporting**：reports optimistic war news with no casualties · `explicit` — [section-004:p0010] “This optimistic, or rather unrealistic, news report had been repeated countless times since the war began”

### `c012` the other researcher

- 名称：the other researcher — [section-004:p0157] “The other researcher was an Eighty-Six.”
- 属性：
  - **ethnicity/status**：Eighty-Six · `explicit` — [section-004:p0157] “The other researcher was an Eighty-Six.”
  - **contribution**：one of the researchers responsible for the fundamental theory and hypothesis of Para-RAID · `inferred` — [section-004:p0156] “The fundamental theory and hypothesis were all the work of other researchers.”；[section-004:p0157] “The other researcher was an Eighty-Six.”
  - **identity record**：name not recorded; received a number as sole identifier · `explicit` — [section-004:p0157] “didn’t have their names recorded”；[section-004:p0157] “they each received a number as their sole identifier”

### `c013` Kujo

- 首次出现于 revision 2
- 名称：Kujo — [section-005:p0004] “Kujo’d died ten days ago.”
- 属性：
  - **status**：dead · `explicit` — [section-005:p0004] “Kujo’d died ten days ago.”
  - **cause of death**：killed by a self-propelled mine during a nighttime rescue mission · `explicit` — [section-005:p0023] “One had latched onto Kujo, who’d mistaken it for an injured soldier.”；[section-005:p0023] “It had been a nighttime battle, a mission to rescue another unit.”

### `c014` Kino

- 首次出现于 revision 2
- 名称：Kino — [section-005:p0008] “Fellow squad member Kino”
- 别名：
  - Fafnir — [section-005:p0177] “Fafnir (Kino)”

### `c015` Lev Aldrecht

- 首次出现于 revision 2
- 名称：Lev Aldrecht — [section-005:p0013] “It was Lev Aldrecht, the Spearhead squadron’s maintenance division captain.”
- 别名：
  - Aldrecht — [section-005:p0021] “Aldrecht smirked bitterly.”
- 属性：
  - **role**：maintenance division captain · `explicit` — [section-005:p0013] “Lev Aldrecht, the Spearhead squadron’s maintenance division captain”
  - **age**：fifty-something · `explicit` — [section-005:p0013] “a fifty-something-year-old member of the maintenance crew”
  - **appearance**：grizzled graying-ash hair, sunglasses, oil-stained work clothes · `explicit` — [section-005:p0013] “His hair was a grizzled graying-ash color, and he wore sunglasses and oil-stained work clothes.”
  - **military history**：survivor who served in the war nine years ago · `explicit` — [section-005:p0013] “being a survivor who’d served in the war nine years ago”

### `c016` Haruto

- 首次出现于 revision 2
- 名称：Haruto — [section-005:p0046] “Haruto, who was a Rubis”
- 别名：
  - Falke — [section-005:p0176] “Falke (Haruto)”
- 属性：
  - **ethnicity**：Rubis · `explicit` — [section-005:p0046] “Haruto, who was a Rubis”

### `c017` Theo

- 首次出现于 revision 2
- 名称：Theo — [section-005:p0046] “Theo, whose hobby was drawing”
- 别名：
  - Laughing Fox — [section-005:p0175] “Laughing Fox (Theo) here.”
- 属性：
  - **appearance**：Jade’s golden hair and emerald eyes; small, slender · `explicit` — [section-005:p0046] “He had a Jade’s golden hair and emerald eyes”；[section-005:p0046] “had a small, slender stature”
  - **age**：turning sixteen this year · `explicit` — [section-005:p0046] “despite turning sixteen this year”
  - **hobby**：drawing · `explicit` — [section-005:p0046] “Theo, whose hobby was drawing”

### `c018` Raiden

- 首次出现于 revision 2
- 名称：Raiden — [section-005:p0093] “the squadron’s vice captain, Raiden”
- 别名：
  - Wehrwolf — [section-005:p0274] “Were you acquainted with Undertaker before you joined this squadron, Wehrwolf?”
- 属性：
  - **role**：squadron vice captain · `explicit` — [section-005:p0093] “the squadron’s vice captain, Raiden”
  - **appearance**：reddish-black hair, sinewy limbs, wild sharp features · `explicit` — [section-005:p0094] “his reddish-black hair, evidence of his pureblood Eisen heritage, was trimmed short”；[section-005:p0094] “his expression and features had a wild, sharp aspect to them”
  - **service as vice captain**：three years · `explicit` — [section-005:p0215] “For three years, Raiden had served as Shin’s vice captain”

### `c019` Kaie Taniya

- 首次出现于 revision 2
- 名称：Kaie Taniya — [section-005:p0224] “Kaie Taniya, rising to the challenge!”
- 别名：
  - Kaie — [section-005:p0059] “What are you doing, Kaie?”
- 属性：
  - **appearance**：black-haired, black-eyed, petite Orienta with a long ponytail · `explicit` — [section-005:p0061] “Kaie, the black-haired, black-eyed, petite Orienta”；[section-005:p0061] “Her ponytail, long enough to look like it could fit on the back of a knight’s helmet”
  - **gender**：girl · `explicit` — [section-005:p0061] “was unmistakably still a girl”

### `c020` Kurena

- 首次出现于 revision 2
- 名称：Kurena — [section-005:p0059] “Kurena stopped the game of tag and called to her.”
- 别名：
  - Gunslinger — [section-005:p0185] “Gunslinger (Kurena)”
- 属性：
  - **appearance**：short-bobbed chestnut Agate hair and catlike Topaz eyes · `explicit` — [section-005:p0059] “She had short-bobbed, chestnut-colored Agate hair and catlike Topaz eyes.”
  - **role**：sniper/sharpshooter · `explicit` — [section-005:p0135] “Kurena’s sixth platoon handled sniping”

### `c021` Anju

- 首次出现于 revision 2
- 名称：Anju — [section-005:p0063] “Anju, who had been rinsing her long silvery-blue hair”
- 别名：
  - Snow Witch — [section-005:p0174] “Snow Witch (Anju)”
- 属性：
  - **appearance**：long silvery-blue hair; pale-blue Celesta eyes · `explicit` — [section-005:p0063] “Anju, who had been rinsing her long silvery-blue hair until now”；[section-005:p0063] “her pale-blue Celesta eyes”
  - **ethnicity**：thick Adularia blood · `explicit` — [section-005:p0063] “she had thick Adularia blood”

### `c022` Daiya

- 首次出现于 revision 2
- 名称：Daiya — [section-005:p0075] “their squad mate Daiya popped out of it.”
- 别名：
  - Black Dog — [section-005:p0174] “Black Dog (Daiya)”
- 属性：
  - **appearance**：blond hair and blue eyes; Sapphira · `explicit` — [section-005:p0075] “Daiya had blond hair and blue eyes, as was typical of the Sapphira.”
  - **gender**：boy · `explicit` — [section-005:p0076] “He was also, incidentally, a boy.”
  - **role**：messenger · `explicit` — [section-005:p0082] “I started working as a messenger today.”

### `c023` Chise

- 首次出现于 revision 2
- 名称：Chise — [section-005:p0120] “—Chise, Kuroto.”

### `c024` Kuroto

- 首次出现于 revision 2
- 名称：Kuroto — [section-005:p0120] “—Chise, Kuroto.”

### `c025` Fido

- 首次出现于 revision 2
- 名称：Fido — [section-005:p0093] “All righty then, Fido.”
- 属性：
  - **type**：Scavenger drone · `explicit` — [section-005:p0103] “Fido was a Scavenger that had been following and obeying Shin for around five years now.”
  - **appearance**：square, angular body on four legs with a crane arm and lens-based optical sensor · `explicit` — [section-005:p0095] “had a square, angular body and ran on four legs”；[section-005:p0096] “Fido immediately extended a crane arm”
  - **service to Shin**：followed and obeyed Shin for around five years · `explicit` — [section-005:p0103] “following and obeying Shin for around five years now”

## 地点（15）

### `l001` Liberté et Égalité

- 名称：Liberté et Égalité — [section-004:p0004] “Liberté et Égalité”
- 属性：
  - **status**：capital of the Republic of San Magnolia · `explicit` — [section-004:p0004] “The main street of the Republic of San Magnolia’s capital, Liberté et Égalité”
  - **appearance**：peaceful and beautiful main street · `explicit` — [section-004:p0004] “was so peaceful and beautiful one would be hard pressed to believe the country had been at war”
  - **paving**：vast, delicately carved stones · `explicit` — [section-004:p0006] “The main street was paved with vast, delicately carved stones”

### `l002` Gran Mule

- 名称：Gran Mule — [section-004:p0014] “the Gran Mule”
- 属性：
  - **structure**：fortification wall that encircled the administrative Sector · `explicit` — [section-004:p0014] “the fortification wall that encircled the administrative Sector, the Gran Mule”
  - **role**：center of command for the entirety of the Republic’s military · `explicit` — [section-004:p0014] “the center of command for the entirety of the Republic’s military”
  - **distance to front lines**：front lines were one hundred kilometers away from its fortress walls · `explicit` — [section-004:p0015] “on the front lines one hundred kilometers away from the fortress walls”

### `l003` Palace Blancneige

- 名称：Palace Blancneige — [section-004:p0014] “Palace Blancneige”
- 属性：
  - **former use**：home to the royal court in days past · `explicit` — [section-004:p0014] “once home to the royal court in days past”
  - **current use**：military’s luxurious headquarters · `explicit` — [section-004:p0014] “now served as the military’s luxurious headquarters”

### `l004` First Sector

- 名称：First Sector — [section-004:p0144] “the First Sector”
- 属性：
  - **status**：Republic’s current administrative center · `explicit` — [section-004:p0144] “The Republic’s current administrative center was the First Sector”
  - **location**：heart of the Republic · `explicit` — [section-004:p0144] “it was at the heart of it all”

### `l005` Eighty-Sixth Sector

- 名称：Eighty-Sixth Sector — [section-004:p0038] “The Eighty-Sixth Sector”
- 属性：
  - **status**：designated a no-man’s-land · `explicit` — [section-004:p0038] “The Eighty-Sixth Sector was designated a no-man’s-land”
  - **population**：Colorata cast outside the Gran Mule to live in internment camps on the front lines · `explicit` — [section-004:p0038] “those Colorata cast outside the Gran Mule to live in internment camps on the front lines”

### `l006` eastern front’s first ward

- 名称：eastern front’s first ward — [section-004:p0099] “the eastern front’s first ward’s first defensive squadron”
- 属性：
  - **importance**：important defensive position where the Legion’s advance was fiercest · `explicit` — [section-004:p0100] “The first ward was certainly an important location; it was an imperative defensive position where the Legion’s advance was the fiercest.”
  - **defended by**：first defensive squadron, the Spearhead squadron · `explicit` — [section-004:p0100] “the first defensive squadron was a significant unit that was single-handedly responsible for the first ward’s defense”

### `l007` eastern front’s ninth ward

- 名称：eastern front’s ninth ward — [section-004:p0027] “the eastern front’s ninth ward”
- 属性：
  - **command**：Lena’s initial command sector · `explicit` — [section-004:p0027] “commanding control officer for the eastern front’s ninth ward, third defensive squadron”
  - **battle**：site of the third squadron’s battle with the Legion · `inferred` — [section-004:p0028] “The third squadron, which was under Lena’s command, had twenty-four units”；[section-004:p0051] “her third squadron lost seven units”

### `l008` seventeenth ward

- 名称：seventeenth ward — [section-004:p0003] “the seventeenth ward”
- 属性：
  - **front**：southern front · `explicit` — [section-004:p0066] “the seventeenth ward of the southern front”
  - **status**：to be abolished and its forces dissolved and discharged · `explicit` — [section-004:p0066] “the seventeenth ward of the southern front will be abolished, and all forces stationed there dissolved and discharged”

### `l009` division commander’s office

- 名称：division commander’s office — [section-004:p0091] “the division commander’s office”
- 属性：
  - **appearance**：golden wallpaper streaked with dark-red stripes · `explicit` — [section-004:p0091] “The golden wallpaper, streaked with dark-red stripes, gave the division commander’s office a profound, dignified atmosphere.”

### `l010` medical room

- 名称：medical room — [section-004:p0128] “the medical room’s reinforced glass window”
- 属性：
  - **feature**：reinforced glass window · `explicit` — [section-004:p0128] “the medical room’s reinforced glass window”

### `l011` ruins of some nameless city

- 首次出现于 revision 2
- 名称：ruins of some nameless city — [section-005:p0093] “ruins of some nameless city”
- 属性：
  - **use**：scavenging site for preserved food, materials, and scrap · `explicit` — [section-005:p0093] “They frequented the ruins of some nameless city when scavenging for preserved foods”

### `l012` point 204

- 首次出现于 revision 2
- 名称：point 204 — [section-005:p0149] “We’ve already deployed at point 204.”
- 属性：
  - **use**：Spearhead squadron's deployment point for the ambush · `explicit` — [section-005:p0149] “We’ve already deployed at point 204.”

### `l013` point 208

- 首次出现于 revision 2
- 名称：point 208 — [section-005:p0148] “We should intercept them at point 208”
- 属性：
  - **use**：optimal intercept point proposed by Handler One · `explicit` — [section-005:p0148] “We should intercept them at point 208”

### `l014` point 304

- 首次出现于 revision 2
- 名称：point 304 — [section-005:p0122] “if we ambush them near point 304”
- 属性：
  - **use**：proposed ambush point near the Legion's route · `explicit` — [section-005:p0122] “if we ambush them near point 304”

### `l015` route twelve

- 首次出现于 revision 2
- 名称：route twelve — [section-005:p0120] “Regroup at the entrance to route twelve.”
- 属性：
  - **use**：regroup point for the hunting party · `explicit` — [section-005:p0120] “Regroup at the entrance to route twelve.”

## 组织（14）

### `g001` Republic of San Magnolia

- 名称：Republic of San Magnolia — [section-004:p0004] “Republic of San Magnolia”
- 别名：
  - Republic of Magnolia — [section-004:p0009] “Hail the Republic of Magnolia.”
  - Republic — [section-004:p0010] “the Republic had failed to regain any of it in nine years of fighting”
- 属性：
  - **war status**：at war for the past nine years · `explicit` — [section-004:p0004] “the country had been at war for the past nine years”
  - **political identity**：first modern democracy in the world · `explicit` — [section-004:p0011] “The Republic prided itself on being the first modern democracy in the world”
  - **native population**：Alba · `explicit` — [section-004:p0011] “The Republic had been the native land of the Alba since ages past”
  - **administrative divisions**：eighty-five administrative Sectors · `explicit` — [section-004:p0012] “the Republic’s eighty-five administrative Sectors”
  - **discriminatory law**：Presidential Order #6609 stripped Colorata civilian rights · `explicit` — [section-004:p0042] “This law acknowledged all persons of Colorata descent within the borders of the Republic as inimical characters and supporters of the Empire and allowed the stripping of their civilian rights.”
  - **military system**：uses Juggernauts with Eighty-Six Processors · `explicit` — [section-004:p0049] “The Eighty-Six who served as pilots were designated information-processing units— Processors”
  - **law**：Eighty-Six are not allowed to carry small firearms to prevent an insurrection · `explicit` — [section-005:p0237] “The Eighty-Six weren’t allowed to carry small firearms, for the sake of preventing an insurrection.”
  - **policy**：Eighty-Six are not buried in graves and collection of their remains is forbidden · `explicit` — [section-005:p0022] “There could be no graves when there were no casualties. Even collecting their remains was forbidden.”

### `g002` Empire of Giad

- 名称：Empire of Giad — [section-004:p0040] “the Empire of Giad”
- 别名：
  - Empire — [section-004:p0009] “the fallen Empire’s evil relics”
  - Giadian Empire — [section-004:p0093] “the militant Giadian Empire”
- 属性：
  - **geopolitical status**：Republic’s eastern neighbor and superpower of the northern continent · `explicit` — [section-004:p0040] “The Republic’s eastern neighbor and superpower of the northern continent, the Empire of Giad”
  - **military action**：declared war on all neighboring countries · `explicit` — [section-004:p0040] “declared war on all its neighboring countries”
  - **weapon**：created and deployed the Legion · `explicit` — [section-004:p0040] “began attacking with an army of the world’s first completely autonomous unmanned combat drone, Legion.”
  - **current status**：appeared to have fallen into ruin four years ago · `explicit` — [section-004:p0121] “it seemed to have fallen into ruin four years ago”
  - **communications**：transmissions suddenly ceased · `explicit` — [section-004:p0121] “The Empire transmissions the Republic was able to intercept in between waves of Eintagsfliege jamming suddenly ceased”

### `g003` Legion

- 名称：Legion — [section-004:p0003] “the Legion”
- 属性：
  - **classification**：unmanned Imperial weapons · `explicit` — [section-004:p0003] “the unmanned Imperial weapons known as the Legion”
  - **classification**：world’s first completely autonomous unmanned combat drone army · `explicit` — [section-004:p0040] “an army of the world’s first completely autonomous unmanned combat drone, Legion”
  - **behavior**：never tire, never disobey orders, never know fear · `explicit` — [section-004:p0093] “the Legion never tired, never disobeyed orders, and never knew fear”
  - **life span**：central processors have fifty thousand hours of operation time per version, just shy of six years · `explicit` — [section-004:p0146] “The Legion’s central processors had a fixed life span programmed into them: fifty thousand hours of operation time per version.”
  - **infrastructure**：fully automated production and repair factories scattered across its territories · `explicit` — [section-004:p0093] “fully automated production and repair factories lay scattered across the depths of their territories”
  - **Eintagsfliege**：flying butterfly-shaped Legion that absorbs/deflects electromagnetic waves and visible light and jams radar/communications · `explicit` — [section-005:p0116] “A swarm of flying Legion, the shape and size of butterflies, that absorbed and deflected electromagnetic waves and rays of visible light—the Eintagsfliege.”
  - **Ameise**：Scout-type Legion with three pairs of legs and 7.56 mm antipersonnel machine guns · `explicit` — [section-005:p0157] “The lightest units, the Scout-type Ameise”；[section-005:p0158] “the 7.56 mm antipersonnel machine guns on their shoulders”
  - **Grauwolf**：Dragoon-type Legion with 57 mm anti-tank multiple-rocket launcher and high-frequency blades · `explicit` — [section-005:p0159] “Carrying a 57 mm anti-tank multiple-rocket launcher on its back, with light reflecting menacingly off the high-frequency blades protruding from its front legs, the Dragoon-type Grauwolf”
  - **Löwe**：Tank-type Legion with eight legs and 120 mm smoothbore turrets · `explicit` — [section-005:p0160] “With their fifty-ton tank frames carried on eight jointed legs, the Tank-type Löwe advanced proudly, their oppressive 120 mm smoothbore turrets gazing ahead.”
  - **Skorpion**：Long-Range Gunner-type Legion with a 155 mm self-propelled shell cannon · `explicit` — [section-005:p0181] “It was artillery support from the 155 mm self-propelled shell-cannon-type Legion, the Long-Range Gunner-type Skorpion.”

### `g004` Republic military

- 名称：Republic military — [section-004:p0008] “the Republic military”
- 别名：
  - Republic Armed Forces — [section-004:p0041] “the Republic Armed Forces”
- 属性：
  - **combat experience**：not a single soldier had ever known true combat · `explicit` — [section-004:p0015] “not a single soldier in the Republic military had ever known true combat”
  - **command center**：Palace Blancneige and Gran Mule · `explicit` — [section-004:p0014] “the center of command for the entirety of the Republic’s military”
  - **combat method**：Juggernauts commanded from control rooms in headquarters · `explicit` — [section-004:p0015] “they were commanded from control rooms in the military’s headquarters”
  - **professions**：communications, transport, analysis, tactical planning, and assorted bureaucracy · `explicit` — [section-004:p0015] “Other professions in the military included communications, transport, analysis, tactical planning, and assorted bureaucracy.”

### `g005` Spearhead squadron

- 名称：Spearhead squadron — [section-004:p0099] “the Spearhead squadron”
- 别名：
  - eastern front’s first ward’s first defensive squadron — [section-004:p0099] “the eastern front’s first ward’s first defensive squadron, also known as the Spearhead squadron”
- 属性：
  - **composition**：veterans from the eastern front; elite unit · `explicit` — [section-004:p0099] “It’s a unit that consists of veterans from the eastern front… You could call it an elite unit.”
  - **responsibility**：single-handedly responsible for the first ward’s defense · `explicit` — [section-004:p0100] “the first defensive squadron was a significant unit that was single-handedly responsible for the first ward’s defense”
  - **captain**：Personal Name: Undertaker · `explicit` — [section-004:p0106] “It’s the Spearhead squadron’s captain unit, Personal Name: Undertaker.”
  - **Handler**：Lena is appointed commanding officer · `explicit` — [section-004:p0125] “I hereby appoint you to the role of commanding officer for the eastern front’s first ward’s first defensive squadron”
  - **size**：twenty-one units · `explicit` — [section-005:p0132] “twenty-one armored weapon systems awakened from their brief slumber”
  - **combat experience**：all members are Name Bearers with four to six years of combat experience · `explicit` — [section-005:p0154] “All members of the Spearhead squadron were distinguished Name Bearers with four to six years of combat experience”

### `g006` third defensive squadron

- 名称：third defensive squadron — [section-004:p0027] “third defensive squadron”
- 别名：
  - third squadron — [section-004:p0028] “The third squadron”
- 属性：
  - **command**：under Lena’s command · `explicit` — [section-004:p0028] “The third squadron, which was under Lena’s command”
  - **size**：twenty-four units · `explicit` — [section-004:p0028] “had twenty-four units”
  - **losses**：lost seven units in battle · `explicit` — [section-004:p0051] “her third squadron lost seven units”

### `g007` Republic Military Industries

- 名称：Republic Military Industries — [section-004:p0049] “Republic Military Industries”
- 别名：
  - RMI — [section-004:p0049] “Republic Military Industries (RMI)”
- 属性：
  - **product**：manufactured the Juggernaut · `explicit` — [section-004:p0049] “manufactured by Republic Military Industries (RMI)”

### `g008` lab division

- 名称：lab division — [section-004:p0019] “the lab division”
- 属性：
  - **affiliation**：Annette is a technical lieutenant affiliated with it · `explicit` — [section-004:p0019] “She was a technical lieutenant affiliated with the lab division”
  - **team**：Para-RAID development team under Annette · `explicit` — [section-004:p0127] “Annette was the officer in charge of the Para-RAID development team”

### `g009` maintenance division

- 首次出现于 revision 2
- 名称：maintenance division — [section-005:p0013] “the Spearhead squadron’s maintenance division captain”

### `g010` first platoon

- 首次出现于 revision 2
- 名称：first platoon — [section-005:p0135] “Shin’s first platoon”

### `g011` third platoon

- 首次出现于 revision 2
- 名称：third platoon — [section-005:p0173] “Third platoon.”

### `g012` fourth platoon

- 首次出现于 revision 2
- 名称：fourth platoon — [section-005:p0135] “Kaie’s fourth platoon”

### `g013` fifth platoon

- 首次出现于 revision 2
- 名称：fifth platoon — [section-005:p0135] “Daiya’s fifth platoon”

### `g014` sixth platoon

- 首次出现于 revision 2
- 名称：sixth platoon — [section-005:p0135] “Kurena’s sixth platoon”

## 关系（有效 41）

- `f000157` `c001` Lena —member\_of→ `g004` Republic military · `explicit` · `current`
  - Lena serves as an officer in the Republic military. — [section-004:p0008] “She was clad in the Republic military’s dark-blue collared uniform for female officers.”
- `f000158` `c001` Lena —commands→ `g006` third defensive squadron · `explicit` · `current`
  - Lena commands the third defensive squadron. — [section-004:p0028] “The third squadron, which was under Lena’s command”
- `f000159` `c001` Lena —commands→ `g005` Spearhead squadron · `explicit` · `current`
  - Lena is appointed commanding officer of the Spearhead squadron. — [section-004:p0125] “I hereby appoint you to the role of commanding officer for the eastern front’s first ward’s first defensive squadron”
- `f000160` `c001` Lena —subordinate\_of→ `c004` Karlstahl · `explicit` · `current`
  - Lena receives orders from and is subordinate to division commander Karlstahl. — [section-004:p0091] “the division commander seated behind the antiquated desk, Commodore Karlstahl”
- `f000161` `c004` Karlstahl —friend\_of→ `c009` Václav · `inferred` · `past`
  - Karlstahl was best friends with Lena’s late father, apparently Václav. — [section-004:p0102] “best friends with Lena’s late father”；[section-004:p0125] “You really do take after Václav”
- `f000162` `c004` Karlstahl —supports→ `c001` Lena · `explicit` · `past`
  - Karlstahl helped arrange Lena’s father’s funeral and supported Lena and her family. — [section-004:p0102] “he helped arrange the funeral, as well as support Lena and her family in various ways”
- `f000163` `c001` Lena —friend\_of→ `c002` Annette · `explicit` · `current`
  - Lena and Annette have been friends since secondary school. — [section-004:p0019] “a friend of Lena’s since secondary school”
- `f000164` `c002` Annette —member\_of→ `g008` lab division · `explicit` · `current`
  - Annette is a technical lieutenant affiliated with the lab division. — [section-004:p0019] “She was a technical lieutenant affiliated with the lab division”
- `f000165` `c002` Annette —daughter\_of→ `c007` Professor Josef von Penrose · `explicit` · `current`
  - Annette is the daughter of Professor Josef von Penrose. — [section-004:p0159] “Annette’s father, Professor Josef von Penrose”
- `f000166` `c005` Pleiades’s Processor —subordinate\_of→ `c001` Lena · `explicit` · `current`
  - Pleiades’s Processor serves as captain of the third squadron under Lena’s command. — [section-004:p0031] “the third squadron’s captain, the Processor operating Personal Name unit Pleiades”
- `f000167` `c006` Shinei Nouzen —subordinate\_of→ `c001` Lena · `explicit` · `current`
  - Undertaker is the captain of the Spearhead squadron under Lena’s command. — [section-004:p0180] “This is the Spearhead squadron’s captain, Personal Name: Undertaker, speaking.”
- `f000168` `c006` Shinei Nouzen —member\_of→ `g005` Spearhead squadron · `explicit` · `current`
  - Undertaker is the Spearhead squadron’s captain. — [section-004:p0180] “This is the Spearhead squadron’s captain, Personal Name: Undertaker, speaking.”
- `f000169` `g005` Spearhead squadron —located\_in→ `l006` eastern front’s first ward · `explicit` · `current`
  - Spearhead squadron is assigned to the eastern front’s first ward. — [section-004:p0099] “the eastern front’s first ward’s first defensive squadron, also known as the Spearhead squadron”
- `f000170` `g006` third defensive squadron —located\_in→ `l007` eastern front’s ninth ward · `explicit` · `current`
  - The third defensive squadron is assigned to the eastern front’s ninth ward. — [section-004:p0027] “commanding control officer for the eastern front’s ninth ward, third defensive squadron”
- `f000171` `g002` Empire of Giad —declared\_war\_on→ `g001` Republic of San Magnolia · `explicit` · `past`
  - The Empire of Giad declared war on its neighboring countries, including the Republic. — [section-004:p0040] “the Empire of Giad, declared war on all its neighboring countries”
- `f000172` `g002` Empire of Giad —deployed→ `g003` Legion · `explicit` · `past`
  - The Empire attacked with an army of Legion drones. — [section-004:p0040] “began attacking with an army of the world’s first completely autonomous unmanned combat drone, Legion.”
- `f000173` `g001` Republic of San Magnolia —at\_war\_with→ `g003` Legion · `explicit` · `current`
  - The Republic is at war with the Legion. — [section-004:p0003] “the Legion have invaded the seventeenth ward today”；[section-004:p0004] “the country had been at war for the past nine years”
- `f000174` `c003` Lena’s mother —parent\_of→ `c001` Lena · `explicit` · `current`
  - Lena’s mother is Lena’s parent. — [section-004:p0068] “Lena’s mother opened her perfectly rouged lips to speak.”
- `f000175` `c011` newscaster —reports\_for→ `g001` Republic of San Magnolia · `explicit` · `current`
  - The newscaster appears on a government-sponsored broadcast. — [section-004:p0065] “This was a government-sponsored broadcast”
- `f000176` `c005` Pleiades’s Processor —member\_of→ `g006` third defensive squadron · `explicit` · `current`
  - Pleiades’s Processor is the captain of the third squadron. — [section-004:p0031] “the third squadron’s captain, the Processor operating Personal Name unit Pleiades”
- `f000177` `c008` Theobald —arranged\_marriage\_candidate\_of→ `c002` Annette · `inferred` · `current`
  - Theobald is the man who came for Annette’s arranged marriage test. — [section-004:p0169] “the guy who came over for my arranged marriage”；[section-004:p0172] “‘To my darling Theobald’”
- `f000289` `c013` Kujo —member\_of→ `g005` Spearhead squadron · `explicit` · `past`
  - Kujo was in the same unit as Shin, the Spearhead squadron. — [section-005:p0025] “Kujo was lucky that in the end he got to be in the same unit as you”
- `f000290` `c014` Kino —member\_of→ `g005` Spearhead squadron · `explicit` · `current`
  - Kino is a fellow squad member of the Spearhead squadron. — [section-005:p0008] “Fellow squad member Kino”
- `f000291` `c015` Lev Aldrecht —captain\_of→ `g009` maintenance division · `explicit` · `current`
  - Lev Aldrecht is the captain of the Spearhead squadron's maintenance division. — [section-005:p0013] “Lev Aldrecht, the Spearhead squadron’s maintenance division captain”
- `f000292` `g009` maintenance division —part\_of→ `g005` Spearhead squadron · `inferred` · `current`
  - The maintenance division is part of the Spearhead squadron. — [section-005:p0013] “the Spearhead squadron’s maintenance division captain”
- `f000293` `c016` Haruto —member\_of→ `g005` Spearhead squadron · `explicit` · `current`
  - Haruto is a squad mate in the Spearhead squadron. — [section-005:p0046] “cut down his squad mate’s joke”
- `f000294` `c017` Theo —member\_of→ `g005` Spearhead squadron · `explicit` · `current`
  - Theo is a squad mate in the Spearhead squadron. — [section-005:p0046] “Theo, whose hobby was drawing, cut down his squad mate’s joke”
- `f000295` `c018` Raiden —vice\_captain\_of→ `g005` Spearhead squadron · `explicit` · `current`
  - Raiden is the vice captain of the Spearhead squadron. — [section-005:p0093] “the squadron’s vice captain, Raiden”
- `f000296` `c018` Raiden —subordinate\_of→ `c006` Shinei Nouzen · `explicit` · `current`
  - Raiden served as Shin's vice captain for three years. — [section-005:p0215] “For three years, Raiden had served as Shin’s vice captain”
- `f000297` `c019` Kaie Taniya —member\_of→ `g012` fourth platoon · `explicit` · `current`
  - Kaie belongs to the fourth platoon. — [section-005:p0135] “Kaie’s fourth platoon”
- `f000298` `c020` Kurena —member\_of→ `g014` sixth platoon · `explicit` · `current`
  - Kurena belongs to the sixth platoon. — [section-005:p0135] “Kurena’s sixth platoon”
- `f000299` `c021` Anju —member\_of→ `g005` Spearhead squadron · `inferred` · `current`
  - Anju is one of the female squadron members of the Spearhead squadron. — [section-005:p0058] “the female squadron members were playing in the water”；[section-005:p0063] “Anju, who had been rinsing her long silvery-blue hair”
- `f000300` `c022` Daiya —member\_of→ `g013` fifth platoon · `explicit` · `current`
  - Daiya belongs to the fifth platoon. — [section-005:p0135] “Daiya’s fifth platoon”
- `f000301` `c022` Daiya —member\_of→ `g005` Spearhead squadron · `explicit` · `current`
  - Daiya is a squad mate in the Spearhead squadron. — [section-005:p0075] “their squad mate Daiya”
- `f000302` `c006` Shinei Nouzen —member\_of→ `g010` first platoon · `explicit` · `current`
  - Shin belongs to the first platoon. — [section-005:p0135] “Shin’s first platoon”
- `f000303` `g010` first platoon —part\_of→ `g005` Spearhead squadron · `inferred` · `current`
  - The first platoon is part of the Spearhead squadron. — [section-005:p0135] “Shin’s first platoon and Kaie’s fourth platoon served as vanguard”
- `f000304` `g011` third platoon —part\_of→ `g005` Spearhead squadron · `inferred` · `current`
  - The third platoon is part of the Spearhead squadron. — [section-005:p0173] “Third platoon.”
- `f000305` `g012` fourth platoon —part\_of→ `g005` Spearhead squadron · `inferred` · `current`
  - The fourth platoon is part of the Spearhead squadron. — [section-005:p0135] “Kaie’s fourth platoon”
- `f000306` `g013` fifth platoon —part\_of→ `g005` Spearhead squadron · `inferred` · `current`
  - The fifth platoon is part of the Spearhead squadron. — [section-005:p0135] “Daiya’s fifth platoon”
- `f000307` `g014` sixth platoon —part\_of→ `g005` Spearhead squadron · `inferred` · `current`
  - The sixth platoon is part of the Spearhead squadron. — [section-005:p0135] “Kurena’s sixth platoon”
- `f000308` `c025` Fido —loyal\_to→ `c006` Shinei Nouzen · `explicit` · `current`
  - Fido the Scavenger has followed and obeyed Shin for around five years. — [section-005:p0103] “Fido was a Scavenger that had been following and obeying Shin for around five years now.”

## 事件（有效 42，按章节顺序，再按章内叙述顺序）

### `section-004` Chapter 1: A Battlefield with Zero Casualties

1. `f000178` A news broadcast announces that Legion forces invaded the seventeenth ward today and were repelled by Juggernauts with no reported loss of life. · `explicit` · `current`
   - 参与者：`c011` newscaster，`g003` Legion，`g001` Republic of San Magnolia；地点：`l008` seventeenth ward；时间：today
   - 证据：[section-004:p0003] “A group of the unmanned Imperial weapons known as the Legion have invaded the seventeenth ward today.”；[section-004:p0003] “no loss of life was reported on our side today yet again”
2. `f000179` Lena walks through the capital’s main street and watches the street-side news broadcast. · `explicit` · `current`
   - 参与者：`c001` Lena；地点：`l001` Liberté et Égalité；时间：—
   - 证据：[section-004:p0007] “A young boy passed by Lena”；[section-004:p0007] “turned her silver eyes to the street-side television’s holo-screen”
3. `f000180` Lena enters the command room and authenticates as Major Vladilena Milizé, commanding control officer for the eastern front’s ninth ward, third defensive squadron. · `explicit` · `current`
   - 参与者：`c001` Lena；地点：`l003` Palace Blancneige；时间：—
   - 证据：[section-004:p0027] “Major Vladilena Milizé, commanding control officer for the eastern front’s ninth ward, third defensive squadron.”
4. `f000181` Lena activates Para-RAID and Resonates with the third squadron captain, Pleiades’s Processor. · `explicit` · `current`
   - 参与者：`c001` Lena，`c005` Pleiades’s Processor；地点：`l003` Palace Blancneige；时间：—
   - 证据：[section-004:p0029] “Activate Para-RAID. Set Resonance target, information-processing unit Pleiades.”；[section-004:p0032] “Handler One to Pleiades—Resonance complete.”
5. `f000182` Nine years earlier, the Empire of Giad declared war on its neighbors and attacked with the autonomous Legion army. · `explicit` · `past`
   - 参与者：`g002` Empire of Giad，`g003` Legion；地点：—；时间：year 358 of the Republic calendar, year 2136 of the global calendar
   - 证据：[section-004:p0040] “the Empire of Giad, declared war on all its neighboring countries and began attacking with an army of the world’s first completely autonomous unmanned combat drone, Legion.”
6. `f000183` The Republic passes Presidential Order #6609, the Special Wartime Peace Preservation Act, stripping Colorata civilians of their rights and isolating them. · `explicit` · `past`
   - 参与者：`g001` Republic of San Magnolia；地点：—；时间：nine years earlier
   - 证据：[section-004:p0042] “Presidential Order #6609. The Special Wartime Peace Preservation Act.”；[section-004:p0042] “allowed the stripping of their civilian rights”
7. `f000184` Two years later, the Republic introduces Juggernauts piloted by Eighty-Six Processors, allowing them to be counted as unmanned drones. · `explicit` · `past`
   - 参与者：`g001` Republic of San Magnolia，`g004` Republic military，`g007` Republic Military Industries；地点：—；时间：two years later
   - 证据：[section-004:p0047] “introduction of drones manned by living soldiers—and all those soldiers were of the Eighty-Six”；[section-004:p0049] “The Eighty-Six who served as pilots were designated information-processing units— Processors”
8. `f000185` The Legion retreats east; Lena’s third squadron loses seven Juggernauts and all their Processors. · `explicit` · `current`
   - 参与者：`c001` Lena，`c005` Pleiades’s Processor，`g003` Legion，`g006` third defensive squadron；地点：`l007` eastern front’s ninth ward；时间：—
   - 证据：[section-004:p0051] “the Legion’s red blips were retreating east”；[section-004:p0051] “her third squadron lost seven units”；[section-004:p0051] “Seven Juggernauts detonated, exploding along with the Processors who piloted them. None survived.”
9. `f000186` Lena thanks Pleiades and apologizes for the seven lost; Pleiades replies with cold contempt. · `explicit` · `current`
   - 参与者：`c001` Lena，`c005` Pleiades’s Processor；地点：`l007` eastern front’s ninth ward；时间：—
   - 证据：[section-004:p0060] “Good job today, Pleiades. And to all other units, too, and the seven who were lost… I’m so, so sorry.”；[section-004:p0063] “Thank you for all the kind words you always offer us, Handler One.”
10. `f000187` The following morning’s news reports the government will reduce the military budget and abolish the seventeenth ward of the southern front. · `explicit` · `current`
   - 参与者：`c011` newscaster，`g001` Republic of San Magnolia；地点：—；时间：The following morning
   - 证据：[section-004:p0066] “the seventeenth ward of the southern front will be abolished”
11. `f000188` At breakfast, Lena’s mother urges her to quit the army and find a groom, and calls the Eighty-Six filthy-colored animals; Lena defends them as Republic citizens. · `explicit` · `current`
   - 参与者：`c001` Lena，`c003` Lena’s mother；地点：—；时间：—
   - 证据：[section-004:p0072] “Lena, isn’t it about time you quit the army and find a groom from a good family?”；[section-004:p0076] “They’re respectable citizens of the Republic, same as you and me.”；[section-004:p0077] “when they’re stained with those filthy colors?”
12. `f000189` Karlstahl tells Lena that another squadron needs a replacement Handler and identifies it as the Spearhead squadron. · `explicit` · `current`
   - 参与者：`c001` Lena，`c004` Karlstahl，`g005` Spearhead squadron；地点：`l009` division commander’s office；时间：—
   - 证据：[section-004:p0097] “another squadron’s Handler recently resigned, and we need to elect a replacement Handler”；[section-004:p0099] “the eastern front’s first ward’s first defensive squadron, also known as the Spearhead squadron”
13. `f000190` Karlstahl warns Lena that the Spearhead captain Undertaker is called the Reaper and has broken past Handlers; Lena accepts the assignment. · `explicit` · `current`
   - 参与者：`c001` Lena，`c004` Karlstahl，`c006` Shinei Nouzen；地点：`l009` division commander’s office；时间：—
   - 证据：[section-004:p0107] “The Handlers who know him seem to call him the Reaper”；[section-004:p0110] “some have committed suicide after resigning”；[section-004:p0114] “I’ll do it. I’ll put all my efforts into serving as the Spearhead squadron’s commanding officer.”
14. `f000191` The Empire of Giad appears to have fallen into ruin four years ago, and its transmissions have ceased. · `explicit` · `past`
   - 参与者：`g002` Empire of Giad，`g003` Legion；地点：—；时间：four years ago
   - 证据：[section-004:p0121] “it seemed to have fallen into ruin four years ago”；[section-004:p0121] “The Empire transmissions the Republic was able to intercept in between waves of Eintagsfliege jamming suddenly ceased”
15. `f000192` Karlstahl formally appoints Lena commanding officer of the eastern front’s first ward’s first defensive squadron, effective that day. · `explicit` · `current`
   - 参与者：`c001` Lena，`c004` Karlstahl，`g005` Spearhead squadron；地点：`l009` division commander’s office；时间：today
   - 证据：[section-004:p0125] “I hereby appoint you to the role of commanding officer for the eastern front’s first ward’s first defensive squadron, effective as of today.”
16. `f000193` Annette updates Lena’s Para-RAID settings and warns that overusing maximum synchronization could collapse her ego. · `explicit` · `current`
   - 参与者：`c001` Lena，`c002` Annette；地点：`l010` medical room；时间：—
   - 证据：[section-004:p0127] “Annette was the officer in charge of the Para-RAID development team”；[section-004:p0158] “if you stay Resonated for too long at maximum synchronization rate, it’s possible for your ego to completely collapse”
17. `f000194` Annette reveals that the Para-RAID’s other researcher was an Eighty-Six whose name was never recorded. · `explicit` · `current`
   - 参与者：`c001` Lena，`c002` Annette，`c012` the other researcher；地点：`l010` medical room；时间：—
   - 证据：[section-004:p0157] “The other researcher was an Eighty-Six.”；[section-004:p0157] “didn’t have their names recorded”
18. `f000195` Annette recounts that her father, Professor Josef von Penrose, was driven mad and killed in a Para-RAID experiment accident. · `explicit` · `past`
   - 参与者：`c002` Annette，`c007` Professor Josef von Penrose；地点：—；时间：—
   - 证据：[section-004:p0159] “was involved in an accident during an experiment that drove him mad and ultimately killed him”
19. `f000196` Lena returns home, activates her Para-RAID, and introduces herself to the Spearhead squadron; Undertaker answers. · `explicit` · `current`
   - 参与者：`c001` Lena，`c006` Shinei Nouzen，`g005` Spearhead squadron；地点：—；时间：—
   - 证据：[section-004:p0177] “Handler One to all units in the Spearhead squadron. It’s a pleasure to meet you all. I will be serving as your commanding officer starting today.”；[section-004:p0180] “This is the Spearhead squadron’s captain, Personal Name: Undertaker, speaking.”
20. `f000197` Lena concludes that the Processors are human beings, not subhuman Eighty-Six. · `explicit` · `current`
   - 参与者：`c001` Lena；地点：—；时间：—
   - 证据：[section-004:p0184] “They were human beings. They were not something subhuman, something known only as an Eighty-Six.”

### `section-005` Chapter 2: All Quiet on the Skeletal Front

1. `f000309` In the Spearhead squadron’s hangar, Shin reads a maintenance report beside a countdown board that Kujo last updated before his death. · `explicit` · `current`
   - 参与者：`c006` Shinei Nouzen，`c013` Kujo；地点：`l006` eastern front’s first ward；时间：—
   - 证据：[section-005:p0003] “In the back of the weatherworn barracks’ hangar, a countdown message was scrawled in big letters with colored chalk”；[section-005:p0004] “Kujo’d died ten days ago.”
2. `f000310` Kujo was killed ten days earlier by a self-propelled mine during a nighttime rescue mission. · `explicit` · `past`
   - 参与者：`c013` Kujo；地点：—；时间：ten days ago
   - 证据：[section-005:p0023] “One had latched onto Kujo, who’d mistaken it for an injured soldier. It had been a nighttime battle, a mission to rescue another unit.”
3. `f000311` Aldrecht confronts Shin about repeatedly damaging his Juggernaut; they discuss repairs, Kujo, and Shin's new Handler. · `explicit` · `current`
   - 参与者：`c015` Lev Aldrecht，`c006` Shinei Nouzen；地点：`l006` eastern front’s first ward；时间：—
   - 证据：[section-005:p0012] “Shin! Shinei Nouzen! Ya fucked it all up again, ya little shit!”；[section-005:p0033] “I heard yer Handler got changed again. What’s the new one like?”
4. `f000312` Haruto brings a freshly killed boar to the barracks kitchen and talks with Theo about cooking duties and the women's laundry; Theo then receives a Para-RAID call from Shin. · `explicit` · `current`
   - 参与者：`c016` Haruto，`c017` Theo，`c006` Shinei Nouzen；地点：`l006` eastern front’s first ward；时间：—
   - 证据：[section-005:p0046] “Having dropped a large boar’s carcass at the back garden’s side entrance”；[section-005:p0058] “Shin… What happened?”
5. `f000313` At the riverbank, the female squadron members bathe and tease Kurena about Shin; Daiya arrives as a messenger and says he has a message from Shin. · `explicit` · `current`
   - 参与者：`c019` Kaie Taniya，`c020` Kurena，`c021` Anju，`c022` Daiya；地点：`l006` eastern front’s first ward；时间：—
   - 证据：[section-005:p0058] “It was near that river’s banks that the female squadron members were playing in the water”；[section-005:p0092] “Yeah. It’s from Shin.”
6. `f000314` In the ruins, Raiden tests Fido by placing a synthetic ration beside preserved bread; Fido flicks the ration away as trash. · `explicit` · `current`
   - 参与者：`c018` Raiden，`c025` Fido；地点：`l011` ruins of some nameless city；时间：—
   - 证据：[section-005:p0096] ““Which one’s trash and which one’s food?” “Pi.” Fido immediately extended a crane arm and flicked the synthetic ration away.”
7. `f000315` Fido leads Raiden to the skeletal corpse of a Republic soldier beneath a sakura tree; Raiden decides the tree is already a good grave and does not collect the remains. · `explicit` · `current`
   - 参与者：`c018` Raiden，`c025` Fido；地点：`l011` ruins of some nameless city；时间：—
   - 证据：[section-005:p0109] ““Nah, it’s okay… This guy’s already got a damn good grave.””；[section-005:p0106] “a discolored, crumbling skeletal corpse resting beneath a large tree”
8. `f000316` Theo relays to Raiden's hunting party that Eintagsfliege are spreading and a Legion attack will come in about two hours; Raiden orders a regroup at route twelve. · `explicit` · `current`
   - 参与者：`c017` Theo，`c018` Raiden，`c023` Chise，`c024` Kuroto；地点：`l011` ruins of some nameless city；时间：about two hours from now
   - 证据：[section-005:p0115] ““Change of forecast. There’s a shower coming.””；[section-005:p0120] “Regroup at the entrance to route twelve.”
9. `f000317` Raiden's hunting party returns; Shin briefs the Spearhead squadron and they board twenty-one Juggernauts for the coming battle. · `explicit` · `current`
   - 参与者：`c006` Shinei Nouzen，`c018` Raiden，`c017` Theo，`g005` Spearhead squadron；地点：`l006` eastern front’s first ward；时间：—
   - 证据：[section-005:p0130] ““We’re all here, right? At attention.””；[section-005:p0132] “twenty-one armored weapon systems awakened from their brief slumber”
10. `f000318` Spearhead deploys in ambush at point 204 along the main street; the Legion approaches in a diamond formation. · `explicit` · `current`
   - 参与者：`g005` Spearhead squadron，`g003` Legion，`c006` Shinei Nouzen；地点：`l012` point 204；时间：—
   - 证据：[section-005:p0149] “We have the enemy’s position confirmed. We’ve already deployed at point 204.”；[section-005:p0137] “The enemy unit employed a textbook diamond formation”
11. `f000319` Shin orders the ambush to open fire, and Spearhead's platoons rake the Legion vanguard and rear. · `explicit` · `current`
   - 参与者：`c006` Shinei Nouzen，`g005` Spearhead squadron，`g003` Legion；地点：`l012` point 204；时间：—
   - 证据：[section-005:p0163] ““Open fire.” At Shin’s order, all units fixed their sights on the targets they’d been appointed and pulled the trigger.”；[section-005:p0164] “The fourth platoon began gunning down the vanguard, while the first platoon bombarded the back line.”
12. `f000320` Undertaker fights in the vanguard, drawing out and destroying Legion units while directing the platoons over the Para-RAID. · `explicit` · `current`
   - 参与者：`c006` Shinei Nouzen，`g005` Spearhead squadron，`g003` Legion；地点：`l012` point 204；时间：—
   - 证据：[section-005:p0170] “Undertaker—ran along the shadows of the ruins of a collapsed building”；[section-005:p0173] “Third platoon. Aggravate the platoons you’re fighting and retreat southeast.”
13. `f000321` Skorpion artillery begins bombarding the battlefield; Handler One transmits the coordinates of three Long-Range Observer Units, and Shin orders Kurena to eliminate them. · `explicit` · `current`
   - 参与者：`c001` Lena，`c006` Shinei Nouzen，`c020` Kurena，`g003` Legion；地点：`l012` point 204；时间：—
   - 证据：[section-005:p0181] “It was artillery support from the 155 mm self-propelled shell-cannon-type Legion, the Long-Range Gunner-type Skorpion.”；[section-005:p0185] ““Gunslinger (Kurena), four units in direction 030, distance 1200.””
14. `f000322` Undertaker restocks ammunition from Fido and tells Raiden he will handle the Löwe tanks. · `explicit` · `current`
   - 参与者：`c006` Shinei Nouzen，`c018` Raiden，`c025` Fido；地点：`l012` point 204；时间：—
   - 证据：[section-005:p0193] “Having run out of ammo, he was being restocked by a Scavenger—Fido, of course.”；[section-005:p0201] ““I’ll handle the Löwe. I’ll leave everyone else and give command over the support to you.””
15. `f000323` Undertaker charges the Löwe tanks, dodges their fire, and destroys multiple Tank types in close combat. · `explicit` · `current`
   - 参与者：`c006` Shinei Nouzen，`g003` Legion；地点：`l012` point 204；时间：—
   - 证据：[section-005:p0207] “In the next moment, Undertaker was airborne.”；[section-005:p0208] “Undertaker fired. A high-speed anti-armor explosive round”；[section-005:p0210] “and shot it down point-blank.”
16. `f000324` The remaining Legion retreats under Skorpion bombardment, leaving Undertaker standing among the wreckage of the Löwe at sunset. · `explicit` · `current`
   - 参与者：`c006` Shinei Nouzen，`g003` Legion；地点：`l012` point 204；时间：—
   - 证据：[section-005:p0218] “The remaining Legion began retreating, assisted by the cover of the Skorpion types’ bombardment.”；[section-005:p0219] “The setting sun’s rays accentuated the silhouette of Undertaker, who stood among the wreckage of the Löwe.”
17. `f000325` After dinner, the squadron holds a sharpshooting tournament using empty cans as targets while Fido rearranges them. · `explicit` · `current`
   - 参与者：`g005` Spearhead squadron，`c025` Fido；地点：`l006` eastern front’s first ward；时间：—
   - 证据：[section-005:p0219] “holding a sharpshooting tournament in front of the hangar”；[section-005:p0228] “Fido picked up the fallen cans and reorganized them in the shape of a tower or a pyramid.”
18. `f000326` The squadron eats a lavish dinner of grilled wild boar and other dishes together outside. · `explicit` · `current`
   - 参与者：`g005` Spearhead squadron；地点：`l006` eastern front’s first ward；时间：—
   - 证据：[section-005:p0229] “They grilled the wild boar they’d caught and served it with gooseberry sauce gathered in hoards from the forest.”；[section-005:p0230] “It was fun, and it was because they all did it together.”
19. `f000327` Anju serves Shin coffee and asks about his book; Shin says focusing on something keeps him from hearing it as loudly. · `explicit` · `current`
   - 参与者：`c021` Anju，`c006` Shinei Nouzen；地点：`l006` eastern front’s first ward；时间：—
   - 证据：[section-005:p0231] “Anju placed a mug of coffee in front of him.”；[section-005:p0234] ““Focusing on something makes it so I don’t hear it as loudly.””
20. `f000328` Handler One calls the squadron after dinner, and Shin answers for everyone. · `explicit` · `current`
   - 参与者：`c001` Lena，`c006` Shinei Nouzen，`g005` Spearhead squadron；地点：`l006` eastern front’s first ward；时间：—
   - 证据：[section-005:p0235] ““Handler One to all units. Are you free right now?””；[section-005:p0237] ““No problems on our side, Handler One. Good job today.” Shin answered on everyone’s behalf.”
21. `f000329` Handler One confronts Shin about sending identical fake battle reports; she orders handwritten reports, and Shin eventually agrees. · `explicit` · `current`
   - 参与者：`c001` Lena，`c006` Shinei Nouzen；地点：`l006` eastern front’s first ward；时间：—
   - 证据：[section-005:p0245] “When I tried reading through them…they were all the same report.”；[section-005:p0266] ““No. Handwritten reports, please.””；[section-005:p0263] ““………Fine, I understand.””
22. `f000330` Handler One asks how long the Processors have served and what Shin plans to do after discharge; Shin says he has never thought about it much. · `explicit` · `current`
   - 参与者：`c001` Lena，`c006` Shinei Nouzen，`c019` Kaie Taniya；地点：`l006` eastern front’s first ward；时间：—
   - 证据：[section-005:p0278] ““Four years for all of us, I think. Oh, Undertaker’s been here the longest. Five years.””；[section-005:p0282] ““Not really. I never thought about it too much.””

## 疑点

### 未解答（13）

- `f000198` Is Annette the same person as the “Henrietta Penrose” mentioned in her own dialogue?（相关：`c002` Annette）
  - 证据：[section-004:p0021] “certified genius Technical Lieutenant Henrietta Penrose”；[section-004:p0019] “she turned to find Annette”
- `f000199` Is Václav the name of Lena’s late father?（相关：`c001` Lena，`c009` Václav）
  - 证据：[section-004:p0102] “best friends with Lena’s late father”；[section-004:p0125] “You really do take after Václav”
- `f000200` Are Pleiades’s Processor and Undertaker the same individual or different squadron captains?（相关：`c005` Pleiades’s Processor，`c006` Shinei Nouzen）
  - 证据：[section-004:p0031] “the third squadron’s captain, the Processor operating Personal Name unit Pleiades”；[section-004:p0180] “This is the Spearhead squadron’s captain, Personal Name: Undertaker, speaking.”
- `f000201` What caused Undertaker’s former Handlers to hear ghosts’ voices or commit suicide?（相关：`c006` Shinei Nouzen）
  - 证据：[section-004:p0111] “they claimed they could ‘hear the ghosts’ voices’ and were haunted by them even after retiring from service”；[section-004:p0110] “some have committed suicide after resigning”
- `f000202` Why did the Empire of Giad fall, and did the Legion turn against it?（相关：`g002` Empire of Giad，`g003` Legion）
  - 证据：[section-004:p0121] “It was uncertain why the Empire fell; did the Legion turn against them, or was there some other reason?”
- `f000203` Who was the Eighty-Six researcher who worked on the Para-RAID’s fundamental theory, and where are they now?（相关：`c012` the other researcher）
  - 证据：[section-004:p0157] “The other researcher was an Eighty-Six.”；[section-004:p0157] “there was no way of even knowing which internment camp they’d been sent to”
- `f000204` What did Professor Josef von Penrose connect to during the accident?（相关：`c007` Professor Josef von Penrose）
  - 证据：[section-004:p0159] “Some believed he connected to somewhere that lay beyond the human collective unconscious.”
- `f000205` Is Theobald definitely the man who came for Annette’s arranged marriage test?（相关：`c002` Annette，`c008` Theobald）
  - 证据：[section-004:p0169] “the guy who came over for my arranged marriage”；[section-004:p0172] “‘To my darling Theobald’”
- `f000331` Who is the person Shin remembers when he thinks of the Bible passage and the words 'And He asked him, What is your name?'（相关：`c006` Shinei Nouzen）
  - 证据：[section-005:p0139] “Someone. The last time he’d seen and heard that person was painted over in his memories, so he couldn’t quite remember.”
- `f000332` Whom does Shin expect to 'come out' during the battle when he thinks 'Ah, you won’t come out this time, either, will you?'（相关：`c006` Shinei Nouzen）
  - 证据：[section-005:p0172] “Ah, you won’t come out this time, either, will you?”
- `f000333` Is Shin's claim that he cannot write or read very well true, given that he is shown reading a philosophy book?（相关：`c006` Shinei Nouzen）
  - 证据：[section-005:p0254] “I can’t write or read very well.”；[section-005:p0259] “Your hobby is reading, after all. Isn’t that thing you’re reading now a philosophy book?”
- `f000334` Does Kurena have romantic feelings for Shin?（相关：`c020` Kurena，`c006` Shinei Nouzen）
  - 证据：[section-005:p0068] “I don’t get what you see in him.”；[section-005:p0072] “I don’t feel anything for Shin”
- `f000335` What happened to the rest of Fido's original unit, and why were only Fido and Shin the survivors?（相关：`c025` Fido，`c006` Shinei Nouzen）
  - 证据：[section-005:p0103] “one of the only two survivors of a battle that wiped everyone else out”

### 已解答（0）


## 修订历史（1 条状态转换）

- `t000001` revision 2 · `section-005` · **supersede**（替代）
  - 旧：`f000006` 名称 “Undertaker”（`c006` Shinei Nouzen）
  - 新：`f000206` 名称 “Shinei Nouzen”（`c006` Shinei Nouzen）
    - 新记录证据：[section-005:p0012] “Shin! Shinei Nouzen!”；[section-005:p0149] “Undertaker to Handler One.”
  - 理由：NEW\_SECTION identifies the Spearhead captain called Undertaker as Shin/Shinei Nouzen, giving him a personal name that is a better primary name than his call sign.
  - 本节证据：[section-005:p0012] “Shin! Shinei Nouzen!”；[section-005:p0149] “Undertaker to Handler One.”
