# Story model 审阅报告：Chapter 1: A Battlefield with Zero Casualties

> ✅ **状态：通过自动校验（结构、ID、引用存在性）；内容是否正确仍需人工审阅**

> ⚠️ **本结果包含 1 处人工修正，不是模型原样输出。**原始输出见 `candidate.original.json`。

## 人工修正

- `characters[1].attributes[6].evidence[0].paragraph_id`：p0164 → p0163（Quote 'Annette smiled mischievously.' occurs verbatim in p0163, not p0164; only the paragraph ID was changed；Claude Code (manual, at user request)，2026-10-26T03:35:50Z）

## 运行信息

- 运行 ID：`20261026T032410Z-2c6f50`；状态：`succeeded`
- Provider：`deepseek`；请求模型：`deepseek-flash`；响应模型：`deepseek-flash`
- Response ID：`461aff59-f61f-4864-b270-dc0b54b34531`；Request ID：—
- 书籍：86—EIGHTY-SIX, Vol. 1；节：`section-004`（Chapter 1）；资源：`EPUB/section-004.xhtml`；段落数：185
- 文本 SHA-256：`d1053fa1bbdd5a1609a15112b64f9fa961aa5395f72a2d80bed92ade53f9d549`
- Prompt SHA-256：`6ae94bfc105ab8fd90929576e68a12601c60e70ed19c2ec7ead173699886ddc0`；Schema SHA-256：`9726d2213492cefd3895a1d4231c9fbbced1c18eeed6ed1e8f814c85fbd821cf`
- Usage：input 14143，output 58662，total 72805

## 阅读须知

- 引用匹配通过只表示该短引用逐字出现在所标段落中，**不代表引用支持对应结论**。每条主张仍需人工阅读原文判断。
- 只输入了本章原文；前文才能确定的身份、指代和原因应出现在“疑点”中，而不是被猜测补全。
- 本实验只处理文字：本章省略了 6 张图片，图片内容未被读取。

## 自动校验

- 人物 12，地点 10，组织 8，关系 21，事件 20，疑点 8
- 证据 240 条，其中逐字匹配 240 条
- 错误 0 个，警告 0 个

## 人物（12）

### `c001` Lena

- 名称证据：
  - [p0007](#p0007) “A young boy passed by Lena” — ✓ 匹配 [0–26]
- 别名：
  - Vladilena Milizé
    - [p0027](#p0027) “Major Vladilena Milizé, commanding control officer for the eastern front’s ninth ward, third defensive squadron.” — ✓ 匹配 [26–138]
  - Handler One
    - [p0177](#p0177) “Handler One to all units in the Spearhead squadron.” — ✓ 匹配 [1–52]
- 属性：
  - **age**：16 · `explicit`
    - [p0008](#p0008) “The sixteen-year-old girl” — ✓ 匹配 [88–113]
  - **rank**：Major · `explicit`
    - [p0027](#p0027) “Major Vladilena Milizé” — ✓ 匹配 [26–48]
  - **affiliation**：Republic military · `explicit`
    - [p0008](#p0008) “She was clad in the Republic military’s dark-blue collared uniform for female officers.” — ✓ 匹配 [0–87]
  - **ethnicity**：Alba; pureblood Celena · `explicit`
    - [p0008](#p0008) “not only an Alba, a descendant of the race native to this land since ages past, but also a pureblood Celena” — ✓ 匹配 [395–502]
  - **appearance**：silver hair and silver eyes · `explicit`
    - [p0008](#p0008) “Her softly flowing, silken hair and long eyelashes were a striking silver, and her large, equally silver eyes” — ✓ 匹配 [256–365]
  - **initial command**：commanding control officer for the eastern front’s ninth ward, third defensive squadron · `explicit`
    - [p0027](#p0027) “commanding control officer for the eastern front’s ninth ward, third defensive squadron” — ✓ 匹配 [50–137]
  - **new command**：commanding officer for the eastern front’s first ward’s first defensive squadron · `explicit`
    - [p0125](#p0125) “I hereby appoint you to the role of commanding officer for the eastern front’s first ward’s first defensive squadron” — ✓ 匹配 [136–252]
  - **family**：daughter of the Milizé household · `explicit`
    - [p0074](#p0074) “daughter of the great Milizé household” — ✓ 匹配 [54–92]
  - **father**：late father was a soldier · `explicit`
    - [p0074](#p0074) “I know your late father was a soldier” — ✓ 匹配 [122–159]

### `c002` Annette

- 名称证据：
  - [p0019](#p0019) “she turned to find Annette” — ✓ 匹配 [147–173]
- 属性：
  - **rank**：Technical lieutenant · `explicit`
    - [p0019](#p0019) “She was a technical lieutenant affiliated with the lab division” — ✓ 匹配 [236–299]
  - **affiliation**：lab division · `explicit`
    - [p0019](#p0019) “She was a technical lieutenant affiliated with the lab division” — ✓ 匹配 [236–299]
  - **friendship**：Lena’s friend since secondary school · `explicit`
    - [p0019](#p0019) “a friend of Lena’s since secondary school” — ✓ 匹配 [304–345]
  - **age**：same age as Lena · `explicit`
    - [p0019](#p0019) “she was currently Lena’s only friend who was the same age” — ✓ 匹配 [381–438]
  - **appearance**：short silver hair and large hanging silver eyes · `explicit`
    - [p0022](#p0022) “Her short hair was an Alba’s silver, and her large, hanging eyes were a similar silvery hue.” — ✓ 匹配 [35–127]
  - **role**：officer in charge of the Para-RAID development team · `explicit`
    - [p0127](#p0127) “Annette was the officer in charge of the Para-RAID development team” — ✓ 匹配 [161–228]
  - **family**：daughter of the Penrose family, formerly a noble house · `inferred`
    - [p0163](#p0163) “Annette smiled mischievously.” — ✓ 匹配 [137–166]
    - [p0165](#p0165) “only the daughter of the Penrose family, formerly a noble house, could afford” — ✓ 匹配 [496–573]
  - **father**：Professor Josef von Penrose · `explicit`
    - [p0159](#p0159) “Annette’s father, Professor Josef von Penrose” — ✓ 匹配 [4–49]

### `c003` Lena’s mother

- 名称证据：
  - [p0068](#p0068) “Lena’s mother opened her perfectly rouged lips to speak.” — ✓ 匹配 [56–112]
- 别名：
  - Mother
    - [p0076](#p0076) “Protecting the motherland is a Republic citizen’s duty and pride, Mother.” — ✓ 匹配 [1–74]
- 属性：
  - **appearance**：dressed in an antiquated gown; perfectly rouged lips · `explicit`
    - [p0068](#p0068) “dressed in an antiquated gown, Lena’s mother opened her perfectly rouged lips” — ✓ 匹配 [25–102]
  - **attitude toward Lena's military career**：urges Lena to quit the army and find a groom from a good family · `explicit`
    - [p0072](#p0072) “Lena, isn’t it about time you quit the army and find a groom from a good family?” — ✓ 匹配 [20–100]
  - **prejudice**：calls the Eighty-Six filthy-colored livestock/animals · `explicit`
    - [p0077](#p0077) “when they’re stained with those filthy colors?” — ✓ 匹配 [105–151]
    - [p0077](#p0077) “letting those animals set foot on Republic soil” — ✓ 匹配 [255–302]

### `c004` Karlstahl

- 名称证据：
  - [p0091](#p0091) “Commodore Karlstahl” — ✓ 匹配 [282–301]
- 别名：
  - Commodore Karlstahl
    - [p0091](#p0091) “Commodore Karlstahl” — ✓ 匹配 [282–301]
  - Uncle Jérôme
    - [p0102](#p0102) “I-I’m sorry, Uncle Jérôme.” — ✓ 匹配 [1–27]
- 属性：
  - **rank**：Commodore · `explicit`
    - [p0091](#p0091) “Commodore Karlstahl” — ✓ 匹配 [282–301]
  - **role**：division commander · `explicit`
    - [p0091](#p0091) “division commander seated behind the antiquated desk” — ✓ 匹配 [228–280]
  - **appearance**：scarred cheeks, beard, tall and broad-shouldered · `explicit`
    - [p0096](#p0096) “Karlstahl’s scarred cheeks slackened into a smile. His beard gave off a feeling of gentle dignity, and his frame was tall and broad-shouldered.” — ✓ 匹配 [0–143]
  - **military history**：fought nine years ago as part of the Republic Armed Forces; one of its sole survivors · `explicit`
    - [p0102](#p0102) “who had fought alongside him nine years ago as part of the now demolished Republic Armed Forces. The two were among its sole survivors.” — ✓ 匹配 [213–348]
  - **support for Lena**：helped arrange her father’s funeral and supported Lena and her family · `explicit`
    - [p0102](#p0102) “he helped arrange the funeral, as well as support Lena and her family in various ways” — ✓ 匹配 [449–534]

### `c005` Pleiades’s Processor

- 名称证据：
  - [p0053](#p0053) “Pleiades’s Processor” — ✓ 匹配 [96–116]
- 别名：
  - Pleiades
    - [p0033](#p0033) “Pleiades to Handler One.” — ✓ 匹配 [1–25]
- 属性：
  - **role**：captain of the third squadron and Processor operating Personal Name unit Pleiades · `explicit`
    - [p0031](#p0031) “the third squadron’s captain, the Processor operating Personal Name unit Pleiades” — ✓ 匹配 [231–312]
  - **voice**：young man, presumably a year or two older than Lena · `explicit`
    - [p0032](#p0032) “the “voice” of a young man, presumably a year or two older than she was” — ✓ 匹配 [109–180]
  - **ethnicity/status**：Eighty-Six · `reported` · 来源 `c005` Pleiades’s Processor
    - [p0037](#p0037) “us subhuman Eighty-Six” — ✓ 匹配 [26–48]
  - **service terms**：agreed to serve five years in exchange for restoration of his family’s civil rights · `explicit`
    - [p0053](#p0053) “the Eighty-Six pilot who agreed to serve on the field of battle for five years in exchange for the restoration of his family’s civil rights” — ✓ 匹配 [117–256]
  - **attitude toward Lena**：scathingly ironic · `explicit`
    - [p0058](#p0058) “Hope you enjoyed watching us pigs squabble through your little telescope, Handler One.” — ✓ 匹配 [25–111]
  - **attitude toward Lena**：cold contempt and hatred · `explicit`
    - [p0064](#p0064) “Cold contempt and hatred were sprinkled into those words.” — ✓ 匹配 [0–57]

### `c006` Undertaker

- 名称证据：
  - [p0106](#p0106) “Personal Name: Undertaker” — ✓ 匹配 [123–148]
- 别名：
  - Reaper
    - [p0107](#p0107) “The Handlers who know him seem to call him the Reaper” — ✓ 匹配 [31–84]
- 属性：
  - **role**：Spearhead squadron’s captain unit · `explicit`
    - [p0106](#p0106) “It’s the Spearhead squadron’s captain unit, Personal Name: Undertaker.” — ✓ 匹配 [79–149]
  - **reputation**：called the Reaper and feared by Handlers · `reported` · 来源 `c004` Karlstahl
    - [p0107](#p0107) “The Handlers who know him seem to call him the Reaper and are all frightened of him” — ✓ 匹配 [31–114]
  - **reputation**：has a tendency to break his Handlers · `reported` · 来源 `c004` Karlstahl
    - [p0107](#p0107) “It seems he has a tendency to…break his Handlers.” — ✓ 匹配 [116–165]
  - **reputation**：many former Handlers requested transfers or resigned; some committed suicide after resigning · `reported` · 来源 `c004` Karlstahl
    - [p0110](#p0110) “an unusually high number of Handlers who were in charge of Undertaker’s squadrons have put in requests to change their assignments or requested to resign from service altogether” — ✓ 匹配 [178–355]
    - [p0110](#p0110) “some have committed suicide after resigning” — ✓ 匹配 [476–519]
  - **voice**：young and serene as a deep forest lake · `explicit`
    - [p0181](#p0181) “his voice was as serene as a deep forest lake” — ✓ 匹配 [93–138]
  - **age/background**：boy roughly Lena’s age, probably originally from a middle-class or higher family · `inferred`
    - [p0181](#p0181) “It was a boy roughly her age, probably originally from a middle-class or higher family.” — ✓ 匹配 [140–227]
  - **ethnicity/status**：Eighty-Six Processor · `inferred`
    - [p0049](#p0049) “The Eighty-Six who served as pilots were designated information-processing units— Processors” — ✓ 匹配 [262–354]
    - [p0180](#p0180) “This is the Spearhead squadron’s captain, Personal Name: Undertaker, speaking.” — ✓ 匹配 [35–113]
  - **demeanor**：detached · `explicit`
    - [p0183](#p0183) “his detached tone” — ✓ 匹配 [65–82]

### `c007` Professor Josef von Penrose

- 名称证据：
  - [p0159](#p0159) “Professor Josef von Penrose” — ✓ 匹配 [22–49]
- 别名：
  - Annette’s father
    - [p0159](#p0159) “Annette’s father, Professor Josef von Penrose” — ✓ 匹配 [4–49]
- 属性：
  - **occupation**：professor · `explicit`
    - [p0159](#p0159) “Professor Josef von Penrose” — ✓ 匹配 [22–49]
  - **relation**：Annette’s father · `explicit`
    - [p0159](#p0159) “Annette’s father, Professor Josef von Penrose” — ✓ 匹配 [4–49]
  - **Para-RAID research**：collaborative research; prepared lab conditions and replicated the phenomenon with recruited test subjects · `explicit`
    - [p0156](#p0156) “Dad was just in charge of preparing the lab conditions and replicating the phenomenon with the recruited test subjects.” — ✓ 匹配 [152–271]
  - **death**：accident during an experiment drove him mad and ultimately killed him · `explicit`
    - [p0159](#p0159) “was involved in an accident during an experiment that drove him mad and ultimately killed him” — ✓ 匹配 [51–144]
  - **accident detail**：RAID Device synchronization rate was accidently set to the theoretical maximum · `explicit`
    - [p0159](#p0159) “The RAID Device’s synchronization rate was accidently set to the theoretical maximum.” — ✓ 匹配 [240–325]
  - **belief about his accident**：some believed he connected somewhere beyond the human collective unconscious · `reported`
    - [p0159](#p0159) “Some believed he connected to somewhere that lay beyond the human collective unconscious.” — ✓ 匹配 [326–415]

### `c008` Theobald

- 名称证据：
  - [p0172](#p0172) “‘To my darling Theobald’” — ✓ 匹配 [167–191]
- 属性：
  - **relation to Annette**：Annette’s arranged-marriage candidate · `inferred`
    - [p0169](#p0169) “the guy who came over for my arranged marriage” — ✓ 匹配 [31–77]
    - [p0172](#p0172) “‘To my darling Theobald’” — ✓ 匹配 [167–191]
  - **personal life**：has a mistress · `explicit`
    - [p0172](#p0172) “apartment he’s renting with his mistress” — ✓ 匹配 [223–263]
  - **reaction to prototype chocolate**：fainted, frothing at the mouth after the fifth prototype chocolate · `explicit`
    - [p0170](#p0170) “he’d fainted, frothing at the mouth after the fifth prototype chocolate” — ✓ 匹配 [9–80]

### `c009` Václav

- 名称证据：
  - [p0125](#p0125) “You really do take after Václav” — ✓ 匹配 [69–100]
- 属性：
  - **possible relation**：may be Lena’s late father · `inferred`
    - [p0102](#p0102) “best friends with Lena’s late father” — ✓ 匹配 [175–211]
    - [p0125](#p0125) “You really do take after Václav” — ✓ 匹配 [69–100]

### `c010` Saint Magnolia

- 名称证据：
  - [p0006](#p0006) “Saint Magnolia” — ✓ 匹配 [101–115]
- 别名：
  - saint of the revolution
    - [p0006](#p0006) “the saint of the revolution, Saint Magnolia” — ✓ 匹配 [72–115]
  - patron saint of the revolution
    - [p0065](#p0065) “patron saint of the revolution” — ✓ 匹配 [650–680]
- 属性：
  - **role**：saint of the revolution · `explicit`
    - [p0006](#p0006) “the saint of the revolution, Saint Magnolia” — ✓ 匹配 [72–115]
  - **role**：patron saint of the revolution · `explicit`
    - [p0065](#p0065) “patron saint of the revolution” — ✓ 匹配 [650–680]
  - **symbol**：her visage appears on a flag at the city hall · `explicit`
    - [p0006](#p0006) “a flag bearing the visage of the saint of the revolution, Saint Magnolia” — ✓ 匹配 [43–115]

### `c011` newscaster

- 名称证据：
  - [p0010](#p0010) “the snowy-haired, silver-eyed alabaster newscaster’s brilliant smile” — ✓ 匹配 [43–111]
- 属性：
  - **appearance**：snowy-haired, silver-eyed Alba · `explicit`
    - [p0010](#p0010) “the snowy-haired, silver-eyed alabaster newscaster” — ✓ 匹配 [43–93]
  - **role**：newscaster on a government-sponsored broadcast · `explicit`
    - [p0065](#p0065) “This was a government-sponsored broadcast” — ✓ 匹配 [424–465]
  - **reporting**：reports optimistic war news with no casualties · `explicit`
    - [p0010](#p0010) “This optimistic, or rather unrealistic, news report had been repeated countless times since the war began” — ✓ 匹配 [113–218]

### `c012` the other researcher

- 名称证据：
  - [p0157](#p0157) “The other researcher was an Eighty-Six.” — ✓ 匹配 [101–140]
- 属性：
  - **ethnicity/status**：Eighty-Six · `explicit`
    - [p0157](#p0157) “The other researcher was an Eighty-Six.” — ✓ 匹配 [101–140]
  - **contribution**：one of the researchers responsible for the fundamental theory and hypothesis of Para-RAID · `inferred`
    - [p0156](#p0156) “The fundamental theory and hypothesis were all the work of other researchers.” — ✓ 匹配 [74–151]
    - [p0157](#p0157) “The other researcher was an Eighty-Six.” — ✓ 匹配 [101–140]
  - **identity record**：name not recorded; received a number as sole identifier · `explicit`
    - [p0157](#p0157) “didn’t have their names recorded” — ✓ 匹配 [188–220]
    - [p0157](#p0157) “they each received a number as their sole identifier” — ✓ 匹配 [257–309]

## 地点（10）

### `l001` Liberté et Égalité

- 名称证据：
  - [p0004](#p0004) “Liberté et Égalité” — ✓ 匹配 [59–77]
- 属性：
  - **status**：capital of the Republic of San Magnolia · `explicit`
    - [p0004](#p0004) “The main street of the Republic of San Magnolia’s capital, Liberté et Égalité” — ✓ 匹配 [0–77]
  - **appearance**：peaceful and beautiful main street · `explicit`
    - [p0004](#p0004) “was so peaceful and beautiful one would be hard pressed to believe the country had been at war” — ✓ 匹配 [79–173]
  - **paving**：vast, delicately carved stones · `explicit`
    - [p0006](#p0006) “The main street was paved with vast, delicately carved stones” — ✓ 匹配 [245–306]

### `l002` Gran Mule

- 名称证据：
  - [p0014](#p0014) “the Gran Mule” — ✓ 匹配 [245–258]
- 属性：
  - **structure**：fortification wall that encircled the administrative Sector · `explicit`
    - [p0014](#p0014) “the fortification wall that encircled the administrative Sector, the Gran Mule” — ✓ 匹配 [180–258]
  - **role**：center of command for the entirety of the Republic’s military · `explicit`
    - [p0014](#p0014) “the center of command for the entirety of the Republic’s military” — ✓ 匹配 [287–352]
  - **distance to front lines**：front lines were one hundred kilometers away from its fortress walls · `explicit`
    - [p0015](#p0015) “on the front lines one hundred kilometers away from the fortress walls” — ✓ 匹配 [46–116]

### `l003` Palace Blancneige

- 名称证据：
  - [p0014](#p0014) “Palace Blancneige” — ✓ 匹配 [48–65]
- 属性：
  - **former use**：home to the royal court in days past · `explicit`
    - [p0014](#p0014) “once home to the royal court in days past” — ✓ 匹配 [67–108]
  - **current use**：military’s luxurious headquarters · `explicit`
    - [p0014](#p0014) “now served as the military’s luxurious headquarters” — ✓ 匹配 [110–161]

### `l004` First Sector

- 名称证据：
  - [p0144](#p0144) “the First Sector” — ✓ 匹配 [49–65]
- 属性：
  - **status**：Republic’s current administrative center · `explicit`
    - [p0144](#p0144) “The Republic’s current administrative center was the First Sector” — ✓ 匹配 [0–65]
  - **location**：heart of the Republic · `explicit`
    - [p0144](#p0144) “it was at the heart of it all” — ✓ 匹配 [71–100]

### `l005` Eighty-Sixth Sector

- 名称证据：
  - [p0038](#p0038) “The Eighty-Sixth Sector” — ✓ 匹配 [150–173]
- 属性：
  - **status**：designated a no-man’s-land · `explicit`
    - [p0038](#p0038) “The Eighty-Sixth Sector was designated a no-man’s-land” — ✓ 匹配 [150–204]
  - **population**：Colorata cast outside the Gran Mule to live in internment camps on the front lines · `explicit`
    - [p0038](#p0038) “those Colorata cast outside the Gran Mule to live in internment camps on the front lines” — ✓ 匹配 [385–473]

### `l006` eastern front’s first ward

- 名称证据：
  - [p0099](#p0099) “the eastern front’s first ward’s first defensive squadron” — ✓ 匹配 [14–71]
- 属性：
  - **importance**：important defensive position where the Legion’s advance was fiercest · `explicit`
    - [p0100](#p0100) “The first ward was certainly an important location; it was an imperative defensive position where the Legion’s advance was the fiercest.” — ✓ 匹配 [58–194]
  - **defended by**：first defensive squadron, the Spearhead squadron · `explicit`
    - [p0100](#p0100) “the first defensive squadron was a significant unit that was single-handedly responsible for the first ward’s defense” — ✓ 匹配 [199–316]

### `l007` eastern front’s ninth ward

- 名称证据：
  - [p0027](#p0027) “the eastern front’s ninth ward” — ✓ 匹配 [81–111]
- 属性：
  - **command**：Lena’s initial command sector · `explicit`
    - [p0027](#p0027) “commanding control officer for the eastern front’s ninth ward, third defensive squadron” — ✓ 匹配 [50–137]
  - **battle**：site of the third squadron’s battle with the Legion · `inferred`
    - [p0028](#p0028) “The third squadron, which was under Lena’s command, had twenty-four units” — ✓ 匹配 [469–542]
    - [p0051](#p0051) “her third squadron lost seven units” — ✓ 匹配 [180–215]

### `l008` seventeenth ward

- 名称证据：
  - [p0003](#p0003) “the seventeenth ward” — ✓ 匹配 [123–143]
- 属性：
  - **front**：southern front · `explicit`
    - [p0066](#p0066) “the seventeenth ward of the southern front” — ✓ 匹配 [162–204]
  - **status**：to be abolished and its forces dissolved and discharged · `explicit`
    - [p0066](#p0066) “the seventeenth ward of the southern front will be abolished, and all forces stationed there dissolved and discharged” — ✓ 匹配 [162–279]

### `l009` division commander’s office

- 名称证据：
  - [p0091](#p0091) “the division commander’s office” — ✓ 匹配 [59–90]
- 属性：
  - **appearance**：golden wallpaper streaked with dark-red stripes · `explicit`
    - [p0091](#p0091) “The golden wallpaper, streaked with dark-red stripes, gave the division commander’s office a profound, dignified atmosphere.” — ✓ 匹配 [0–124]

### `l010` medical room

- 名称证据：
  - [p0128](#p0128) “the medical room’s reinforced glass window” — ✓ 匹配 [103–145]
- 属性：
  - **feature**：reinforced glass window · `explicit`
    - [p0128](#p0128) “the medical room’s reinforced glass window” — ✓ 匹配 [103–145]

## 组织（8）

### `g001` Republic of San Magnolia

- 名称证据：
  - [p0004](#p0004) “Republic of San Magnolia” — ✓ 匹配 [23–47]
- 别名：
  - Republic of Magnolia
    - [p0009](#p0009) “Hail the Republic of Magnolia.” — ✓ 匹配 [439–469]
  - Republic
    - [p0010](#p0010) “the Republic had failed to regain any of it in nine years of fighting” — ✓ 匹配 [411–480]
- 属性：
  - **war status**：at war for the past nine years · `explicit`
    - [p0004](#p0004) “the country had been at war for the past nine years” — ✓ 匹配 [146–197]
  - **political identity**：first modern democracy in the world · `explicit`
    - [p0011](#p0011) “The Republic prided itself on being the first modern democracy in the world” — ✓ 匹配 [228–303]
  - **native population**：Alba · `explicit`
    - [p0011](#p0011) “The Republic had been the native land of the Alba since ages past” — ✓ 匹配 [362–427]
  - **administrative divisions**：eighty-five administrative Sectors · `explicit`
    - [p0012](#p0012) “the Republic’s eighty-five administrative Sectors” — ✓ 匹配 [117–166]
  - **discriminatory law**：Presidential Order #6609 stripped Colorata civilian rights · `explicit`
    - [p0042](#p0042) “This law acknowledged all persons of Colorata descent within the borders of the Republic as inimical characters and supporters of the Empire and allowed the stripping of their civilian rights.” — ✓ 匹配 [188–380]
  - **military system**：uses Juggernauts with Eighty-Six Processors · `explicit`
    - [p0049](#p0049) “The Eighty-Six who served as pilots were designated information-processing units— Processors” — ✓ 匹配 [262–354]

### `g002` Empire of Giad

- 名称证据：
  - [p0040](#p0040) “the Empire of Giad” — ✓ 匹配 [74–92]
- 别名：
  - Empire
    - [p0009](#p0009) “the fallen Empire’s evil relics” — ✓ 匹配 [329–360]
  - Giadian Empire
    - [p0093](#p0093) “the militant Giadian Empire” — ✓ 匹配 [108–135]
- 属性：
  - **geopolitical status**：Republic’s eastern neighbor and superpower of the northern continent · `explicit`
    - [p0040](#p0040) “The Republic’s eastern neighbor and superpower of the northern continent, the Empire of Giad” — ✓ 匹配 [0–92]
  - **military action**：declared war on all neighboring countries · `explicit`
    - [p0040](#p0040) “declared war on all its neighboring countries” — ✓ 匹配 [94–139]
  - **weapon**：created and deployed the Legion · `explicit`
    - [p0040](#p0040) “began attacking with an army of the world’s first completely autonomous unmanned combat drone, Legion.” — ✓ 匹配 [144–246]
  - **current status**：appeared to have fallen into ruin four years ago · `explicit`
    - [p0121](#p0121) “it seemed to have fallen into ruin four years ago” — ✓ 匹配 [95–144]
  - **communications**：transmissions suddenly ceased · `explicit`
    - [p0121](#p0121) “The Empire transmissions the Republic was able to intercept in between waves of Eintagsfliege jamming suddenly ceased” — ✓ 匹配 [146–263]

### `g003` Legion

- 名称证据：
  - [p0003](#p0003) “the Legion” — ✓ 匹配 [99–109]
- 属性：
  - **classification**：unmanned Imperial weapons · `explicit`
    - [p0003](#p0003) “the unmanned Imperial weapons known as the Legion” — ✓ 匹配 [60–109]
  - **classification**：world’s first completely autonomous unmanned combat drone army · `explicit`
    - [p0040](#p0040) “an army of the world’s first completely autonomous unmanned combat drone, Legion” — ✓ 匹配 [165–245]
  - **behavior**：never tire, never disobey orders, never know fear · `explicit`
    - [p0093](#p0093) “the Legion never tired, never disobeyed orders, and never knew fear” — ✓ 匹配 [436–503]
  - **life span**：central processors have fifty thousand hours of operation time per version, just shy of six years · `explicit`
    - [p0146](#p0146) “The Legion’s central processors had a fixed life span programmed into them: fifty thousand hours of operation time per version.” — ✓ 匹配 [156–283]
  - **infrastructure**：fully automated production and repair factories scattered across its territories · `explicit`
    - [p0093](#p0093) “fully automated production and repair factories lay scattered across the depths of their territories” — ✓ 匹配 [544–644]

### `g004` Republic military

- 名称证据：
  - [p0008](#p0008) “the Republic military” — ✓ 匹配 [16–37]
- 别名：
  - Republic Armed Forces
    - [p0041](#p0041) “the Republic Armed Forces” — ✓ 匹配 [56–81]
- 属性：
  - **combat experience**：not a single soldier had ever known true combat · `explicit`
    - [p0015](#p0015) “not a single soldier in the Republic military had ever known true combat” — ✓ 匹配 [684–756]
  - **command center**：Palace Blancneige and Gran Mule · `explicit`
    - [p0014](#p0014) “the center of command for the entirety of the Republic’s military” — ✓ 匹配 [287–352]
  - **combat method**：Juggernauts commanded from control rooms in headquarters · `explicit`
    - [p0015](#p0015) “they were commanded from control rooms in the military’s headquarters” — ✓ 匹配 [174–243]
  - **professions**：communications, transport, analysis, tactical planning, and assorted bureaucracy · `explicit`
    - [p0015](#p0015) “Other professions in the military included communications, transport, analysis, tactical planning, and assorted bureaucracy.” — ✓ 匹配 [543–667]

### `g005` Spearhead squadron

- 名称证据：
  - [p0099](#p0099) “the Spearhead squadron” — ✓ 匹配 [87–109]
- 别名：
  - eastern front’s first ward’s first defensive squadron
    - [p0099](#p0099) “the eastern front’s first ward’s first defensive squadron, also known as the Spearhead squadron” — ✓ 匹配 [14–109]
- 属性：
  - **composition**：veterans from the eastern front; elite unit · `explicit`
    - [p0099](#p0099) “It’s a unit that consists of veterans from the eastern front… You could call it an elite unit.” — ✓ 匹配 [111–205]
  - **responsibility**：single-handedly responsible for the first ward’s defense · `explicit`
    - [p0100](#p0100) “the first defensive squadron was a significant unit that was single-handedly responsible for the first ward’s defense” — ✓ 匹配 [199–316]
  - **captain**：Personal Name: Undertaker · `explicit`
    - [p0106](#p0106) “It’s the Spearhead squadron’s captain unit, Personal Name: Undertaker.” — ✓ 匹配 [79–149]
  - **Handler**：Lena is appointed commanding officer · `explicit`
    - [p0125](#p0125) “I hereby appoint you to the role of commanding officer for the eastern front’s first ward’s first defensive squadron” — ✓ 匹配 [136–252]

### `g006` third defensive squadron

- 名称证据：
  - [p0027](#p0027) “third defensive squadron” — ✓ 匹配 [113–137]
- 别名：
  - third squadron
    - [p0028](#p0028) “The third squadron” — ✓ 匹配 [469–487]
- 属性：
  - **command**：under Lena’s command · `explicit`
    - [p0028](#p0028) “The third squadron, which was under Lena’s command” — ✓ 匹配 [469–519]
  - **size**：twenty-four units · `explicit`
    - [p0028](#p0028) “had twenty-four units” — ✓ 匹配 [521–542]
  - **losses**：lost seven units in battle · `explicit`
    - [p0051](#p0051) “her third squadron lost seven units” — ✓ 匹配 [180–215]

### `g007` Republic Military Industries

- 名称证据：
  - [p0049](#p0049) “Republic Military Industries” — ✓ 匹配 [83–111]
- 别名：
  - RMI
    - [p0049](#p0049) “Republic Military Industries (RMI)” — ✓ 匹配 [83–117]
- 属性：
  - **product**：manufactured the Juggernaut · `explicit`
    - [p0049](#p0049) “manufactured by Republic Military Industries (RMI)” — ✓ 匹配 [67–117]

### `g008` lab division

- 名称证据：
  - [p0019](#p0019) “the lab division” — ✓ 匹配 [283–299]
- 属性：
  - **affiliation**：Annette is a technical lieutenant affiliated with it · `explicit`
    - [p0019](#p0019) “She was a technical lieutenant affiliated with the lab division” — ✓ 匹配 [236–299]
  - **team**：Para-RAID development team under Annette · `explicit`
    - [p0127](#p0127) “Annette was the officer in charge of the Para-RAID development team” — ✓ 匹配 [161–228]

## 关系（21）

- **`r001`** `c001` Lena —member\_of→ `g004` Republic military · `explicit` · `current`
  - Lena serves as an officer in the Republic military.
  - [p0008](#p0008) “She was clad in the Republic military’s dark-blue collared uniform for female officers.” — ✓ 匹配 [0–87]
- **`r002`** `c001` Lena —commands→ `g006` third defensive squadron · `explicit` · `current`
  - Lena commands the third defensive squadron.
  - [p0028](#p0028) “The third squadron, which was under Lena’s command” — ✓ 匹配 [469–519]
- **`r003`** `c001` Lena —commands→ `g005` Spearhead squadron · `explicit` · `current`
  - Lena is appointed commanding officer of the Spearhead squadron.
  - [p0125](#p0125) “I hereby appoint you to the role of commanding officer for the eastern front’s first ward’s first defensive squadron” — ✓ 匹配 [136–252]
- **`r004`** `c001` Lena —subordinate\_of→ `c004` Karlstahl · `explicit` · `current`
  - Lena receives orders from and is subordinate to division commander Karlstahl.
  - [p0091](#p0091) “the division commander seated behind the antiquated desk, Commodore Karlstahl” — ✓ 匹配 [224–301]
- **`r005`** `c004` Karlstahl —friend\_of→ `c009` Václav · `inferred` · `past`
  - Karlstahl was best friends with Lena’s late father, apparently Václav.
  - [p0102](#p0102) “best friends with Lena’s late father” — ✓ 匹配 [175–211]
  - [p0125](#p0125) “You really do take after Václav” — ✓ 匹配 [69–100]
- **`r006`** `c004` Karlstahl —supports→ `c001` Lena · `explicit` · `past`
  - Karlstahl helped arrange Lena’s father’s funeral and supported Lena and her family.
  - [p0102](#p0102) “he helped arrange the funeral, as well as support Lena and her family in various ways” — ✓ 匹配 [449–534]
- **`r007`** `c001` Lena —friend\_of→ `c002` Annette · `explicit` · `current`
  - Lena and Annette have been friends since secondary school.
  - [p0019](#p0019) “a friend of Lena’s since secondary school” — ✓ 匹配 [304–345]
- **`r008`** `c002` Annette —member\_of→ `g008` lab division · `explicit` · `current`
  - Annette is a technical lieutenant affiliated with the lab division.
  - [p0019](#p0019) “She was a technical lieutenant affiliated with the lab division” — ✓ 匹配 [236–299]
- **`r009`** `c002` Annette —daughter\_of→ `c007` Professor Josef von Penrose · `explicit` · `current`
  - Annette is the daughter of Professor Josef von Penrose.
  - [p0159](#p0159) “Annette’s father, Professor Josef von Penrose” — ✓ 匹配 [4–49]
- **`r010`** `c005` Pleiades’s Processor —subordinate\_of→ `c001` Lena · `explicit` · `current`
  - Pleiades’s Processor serves as captain of the third squadron under Lena’s command.
  - [p0031](#p0031) “the third squadron’s captain, the Processor operating Personal Name unit Pleiades” — ✓ 匹配 [231–312]
- **`r011`** `c006` Undertaker —subordinate\_of→ `c001` Lena · `explicit` · `current`
  - Undertaker is the captain of the Spearhead squadron under Lena’s command.
  - [p0180](#p0180) “This is the Spearhead squadron’s captain, Personal Name: Undertaker, speaking.” — ✓ 匹配 [35–113]
- **`r012`** `c006` Undertaker —member\_of→ `g005` Spearhead squadron · `explicit` · `current`
  - Undertaker is the Spearhead squadron’s captain.
  - [p0180](#p0180) “This is the Spearhead squadron’s captain, Personal Name: Undertaker, speaking.” — ✓ 匹配 [35–113]
- **`r013`** `g005` Spearhead squadron —located\_in→ `l006` eastern front’s first ward · `explicit` · `current`
  - Spearhead squadron is assigned to the eastern front’s first ward.
  - [p0099](#p0099) “the eastern front’s first ward’s first defensive squadron, also known as the Spearhead squadron” — ✓ 匹配 [14–109]
- **`r014`** `g006` third defensive squadron —located\_in→ `l007` eastern front’s ninth ward · `explicit` · `current`
  - The third defensive squadron is assigned to the eastern front’s ninth ward.
  - [p0027](#p0027) “commanding control officer for the eastern front’s ninth ward, third defensive squadron” — ✓ 匹配 [50–137]
- **`r015`** `g002` Empire of Giad —declared\_war\_on→ `g001` Republic of San Magnolia · `explicit` · `past`
  - The Empire of Giad declared war on its neighboring countries, including the Republic.
  - [p0040](#p0040) “the Empire of Giad, declared war on all its neighboring countries” — ✓ 匹配 [74–139]
- **`r016`** `g002` Empire of Giad —deployed→ `g003` Legion · `explicit` · `past`
  - The Empire attacked with an army of Legion drones.
  - [p0040](#p0040) “began attacking with an army of the world’s first completely autonomous unmanned combat drone, Legion.” — ✓ 匹配 [144–246]
- **`r017`** `g001` Republic of San Magnolia —at\_war\_with→ `g003` Legion · `explicit` · `current`
  - The Republic is at war with the Legion.
  - [p0003](#p0003) “the Legion have invaded the seventeenth ward today” — ✓ 匹配 [99–149]
  - [p0004](#p0004) “the country had been at war for the past nine years” — ✓ 匹配 [146–197]
- **`r018`** `c003` Lena’s mother —parent\_of→ `c001` Lena · `explicit` · `current`
  - Lena’s mother is Lena’s parent.
  - [p0068](#p0068) “Lena’s mother opened her perfectly rouged lips to speak.” — ✓ 匹配 [56–112]
- **`r019`** `c011` newscaster —reports\_for→ `g001` Republic of San Magnolia · `explicit` · `current`
  - The newscaster appears on a government-sponsored broadcast.
  - [p0065](#p0065) “This was a government-sponsored broadcast” — ✓ 匹配 [424–465]
- **`r020`** `c005` Pleiades’s Processor —member\_of→ `g006` third defensive squadron · `explicit` · `current`
  - Pleiades’s Processor is the captain of the third squadron.
  - [p0031](#p0031) “the third squadron’s captain, the Processor operating Personal Name unit Pleiades” — ✓ 匹配 [231–312]
- **`r021`** `c008` Theobald —arranged\_marriage\_candidate\_of→ `c002` Annette · `inferred` · `current`
  - Theobald is the man who came for Annette’s arranged marriage test.
  - [p0169](#p0169) “the guy who came over for my arranged marriage” — ✓ 匹配 [31–77]
  - [p0172](#p0172) “‘To my darling Theobald’” — ✓ 匹配 [167–191]

## 事件（20，按本章叙述顺序）

1. **`e001`** A news broadcast announces that Legion forces invaded the seventeenth ward today and were repelled by Juggernauts with no reported loss of life. · `explicit` · `current`
   - 参与者：`c011` newscaster，`g003` Legion，`g001` Republic of San Magnolia；地点：`l008` seventeenth ward；时间：today
   - [p0003](#p0003) “A group of the unmanned Imperial weapons known as the Legion have invaded the seventeenth ward today.” — ✓ 匹配 [49–150]
   - [p0003](#p0003) “no loss of life was reported on our side today yet again” — ✓ 匹配 [355–411]
2. **`e002`** Lena walks through the capital’s main street and watches the street-side news broadcast. · `explicit` · `current`
   - 参与者：`c001` Lena；地点：`l001` Liberté et Égalité；时间：—
   - [p0007](#p0007) “A young boy passed by Lena” — ✓ 匹配 [0–26]
   - [p0007](#p0007) “turned her silver eyes to the street-side television’s holo-screen” — ✓ 匹配 [229–295]
3. **`e003`** Lena enters the command room and authenticates as Major Vladilena Milizé, commanding control officer for the eastern front’s ninth ward, third defensive squadron. · `explicit` · `current`
   - 参与者：`c001` Lena；地点：`l003` Palace Blancneige；时间：—
   - [p0027](#p0027) “Major Vladilena Milizé, commanding control officer for the eastern front’s ninth ward, third defensive squadron.” — ✓ 匹配 [26–138]
4. **`e004`** Lena activates Para-RAID and Resonates with the third squadron captain, Pleiades’s Processor. · `explicit` · `current`
   - 参与者：`c001` Lena，`c005` Pleiades’s Processor；地点：`l003` Palace Blancneige；时间：—
   - [p0029](#p0029) “Activate Para-RAID. Set Resonance target, information-processing unit Pleiades.” — ✓ 匹配 [1–80]
   - [p0032](#p0032) “Handler One to Pleiades—Resonance complete.” — ✓ 匹配 [1–44]
5. **`e005`** Nine years earlier, the Empire of Giad declared war on its neighbors and attacked with the autonomous Legion army. · `explicit` · `past`
   - 参与者：`g002` Empire of Giad，`g003` Legion；地点：—；时间：year 358 of the Republic calendar, year 2136 of the global calendar
   - [p0040](#p0040) “the Empire of Giad, declared war on all its neighboring countries and began attacking with an army of the world’s first completely autonomous unmanned combat drone, Legion.” — ✓ 匹配 [74–246]
6. **`e006`** The Republic passes Presidential Order #6609, the Special Wartime Peace Preservation Act, stripping Colorata civilians of their rights and isolating them. · `explicit` · `past`
   - 参与者：`g001` Republic of San Magnolia；地点：—；时间：nine years earlier
   - [p0042](#p0042) “Presidential Order #6609. The Special Wartime Peace Preservation Act.” — ✓ 匹配 [118–187]
   - [p0042](#p0042) “allowed the stripping of their civilian rights” — ✓ 匹配 [333–379]
7. **`e007`** Two years later, the Republic introduces Juggernauts piloted by Eighty-Six Processors, allowing them to be counted as unmanned drones. · `explicit` · `past`
   - 参与者：`g001` Republic of San Magnolia，`g004` Republic military，`g007` Republic Military Industries；地点：—；时间：two years later
   - [p0047](#p0047) “introduction of drones manned by living soldiers—and all those soldiers were of the Eighty-Six” — ✓ 匹配 [155–249]
   - [p0049](#p0049) “The Eighty-Six who served as pilots were designated information-processing units— Processors” — ✓ 匹配 [262–354]
8. **`e008`** The Legion retreats east; Lena’s third squadron loses seven Juggernauts and all their Processors. · `explicit` · `current`
   - 参与者：`c001` Lena，`c005` Pleiades’s Processor，`g003` Legion，`g006` third defensive squadron；地点：`l007` eastern front’s ninth ward；时间：—
   - [p0051](#p0051) “the Legion’s red blips were retreating east” — ✓ 匹配 [16–59]
   - [p0051](#p0051) “her third squadron lost seven units” — ✓ 匹配 [180–215]
   - [p0051](#p0051) “Seven Juggernauts detonated, exploding along with the Processors who piloted them. None survived.” — ✓ 匹配 [250–347]
9. **`e009`** Lena thanks Pleiades and apologizes for the seven lost; Pleiades replies with cold contempt. · `explicit` · `current`
   - 参与者：`c001` Lena，`c005` Pleiades’s Processor；地点：`l007` eastern front’s ninth ward；时间：—
   - [p0060](#p0060) “Good job today, Pleiades. And to all other units, too, and the seven who were lost… I’m so, so sorry.” — ✓ 匹配 [1–102]
   - [p0063](#p0063) “Thank you for all the kind words you always offer us, Handler One.” — ✓ 匹配 [2–68]
10. **`e010`** The following morning’s news reports the government will reduce the military budget and abolish the seventeenth ward of the southern front. · `explicit` · `current`
   - 参与者：`c011` newscaster，`g001` Republic of San Magnolia；地点：—；时间：The following morning
   - [p0066](#p0066) “the seventeenth ward of the southern front will be abolished” — ✓ 匹配 [162–222]
11. **`e011`** At breakfast, Lena’s mother urges her to quit the army and find a groom, and calls the Eighty-Six filthy-colored animals; Lena defends them as Republic citizens. · `explicit` · `current`
   - 参与者：`c001` Lena，`c003` Lena’s mother；地点：—；时间：—
   - [p0072](#p0072) “Lena, isn’t it about time you quit the army and find a groom from a good family?” — ✓ 匹配 [20–100]
   - [p0076](#p0076) “They’re respectable citizens of the Republic, same as you and me.” — ✓ 匹配 [114–179]
   - [p0077](#p0077) “when they’re stained with those filthy colors?” — ✓ 匹配 [105–151]
12. **`e012`** Karlstahl tells Lena that another squadron needs a replacement Handler and identifies it as the Spearhead squadron. · `explicit` · `current`
   - 参与者：`c001` Lena，`c004` Karlstahl，`g005` Spearhead squadron；地点：`l009` division commander’s office；时间：—
   - [p0097](#p0097) “another squadron’s Handler recently resigned, and we need to elect a replacement Handler” — ✓ 匹配 [69–157]
   - [p0099](#p0099) “the eastern front’s first ward’s first defensive squadron, also known as the Spearhead squadron” — ✓ 匹配 [14–109]
13. **`e013`** Karlstahl warns Lena that the Spearhead captain Undertaker is called the Reaper and has broken past Handlers; Lena accepts the assignment. · `explicit` · `current`
   - 参与者：`c001` Lena，`c004` Karlstahl，`c006` Undertaker；地点：`l009` division commander’s office；时间：—
   - [p0107](#p0107) “The Handlers who know him seem to call him the Reaper” — ✓ 匹配 [31–84]
   - [p0110](#p0110) “some have committed suicide after resigning” — ✓ 匹配 [476–519]
   - [p0114](#p0114) “I’ll do it. I’ll put all my efforts into serving as the Spearhead squadron’s commanding officer.” — ✓ 匹配 [31–127]
14. **`e014`** The Empire of Giad appears to have fallen into ruin four years ago, and its transmissions have ceased. · `explicit` · `past`
   - 参与者：`g002` Empire of Giad，`g003` Legion；地点：—；时间：four years ago
   - [p0121](#p0121) “it seemed to have fallen into ruin four years ago” — ✓ 匹配 [95–144]
   - [p0121](#p0121) “The Empire transmissions the Republic was able to intercept in between waves of Eintagsfliege jamming suddenly ceased” — ✓ 匹配 [146–263]
15. **`e015`** Karlstahl formally appoints Lena commanding officer of the eastern front’s first ward’s first defensive squadron, effective that day. · `explicit` · `current`
   - 参与者：`c001` Lena，`c004` Karlstahl，`g005` Spearhead squadron；地点：`l009` division commander’s office；时间：today
   - [p0125](#p0125) “I hereby appoint you to the role of commanding officer for the eastern front’s first ward’s first defensive squadron, effective as of today.” — ✓ 匹配 [136–276]
16. **`e016`** Annette updates Lena’s Para-RAID settings and warns that overusing maximum synchronization could collapse her ego. · `explicit` · `current`
   - 参与者：`c001` Lena，`c002` Annette；地点：`l010` medical room；时间：—
   - [p0127](#p0127) “Annette was the officer in charge of the Para-RAID development team” — ✓ 匹配 [161–228]
   - [p0158](#p0158) “if you stay Resonated for too long at maximum synchronization rate, it’s possible for your ego to completely collapse” — ✓ 匹配 [188–305]
17. **`e017`** Annette reveals that the Para-RAID’s other researcher was an Eighty-Six whose name was never recorded. · `explicit` · `current`
   - 参与者：`c001` Lena，`c002` Annette，`c012` the other researcher；地点：`l010` medical room；时间：—
   - [p0157](#p0157) “The other researcher was an Eighty-Six.” — ✓ 匹配 [101–140]
   - [p0157](#p0157) “didn’t have their names recorded” — ✓ 匹配 [188–220]
18. **`e018`** Annette recounts that her father, Professor Josef von Penrose, was driven mad and killed in a Para-RAID experiment accident. · `explicit` · `past`
   - 参与者：`c002` Annette，`c007` Professor Josef von Penrose；地点：—；时间：—
   - [p0159](#p0159) “was involved in an accident during an experiment that drove him mad and ultimately killed him” — ✓ 匹配 [51–144]
19. **`e019`** Lena returns home, activates her Para-RAID, and introduces herself to the Spearhead squadron; Undertaker answers. · `explicit` · `current`
   - 参与者：`c001` Lena，`c006` Undertaker，`g005` Spearhead squadron；地点：—；时间：—
   - [p0177](#p0177) “Handler One to all units in the Spearhead squadron. It’s a pleasure to meet you all. I will be serving as your commanding officer starting today.” — ✓ 匹配 [1–146]
   - [p0180](#p0180) “This is the Spearhead squadron’s captain, Personal Name: Undertaker, speaking.” — ✓ 匹配 [35–113]
20. **`e020`** Lena concludes that the Processors are human beings, not subhuman Eighty-Six. · `explicit` · `current`
   - 参与者：`c001` Lena；地点：—；时间：—
   - [p0184](#p0184) “They were human beings. They were not something subhuman, something known only as an Eighty-Six.” — ✓ 匹配 [0–96]

## 疑点（8）

- Is Annette the same person as the “Henrietta Penrose” mentioned in her own dialogue?（相关：`c002` Annette）
  - [p0021](#p0021) “certified genius Technical Lieutenant Henrietta Penrose” — ✓ 匹配 [186–241]
  - [p0019](#p0019) “she turned to find Annette” — ✓ 匹配 [147–173]
- Is Václav the name of Lena’s late father?（相关：`c001` Lena，`c009` Václav）
  - [p0102](#p0102) “best friends with Lena’s late father” — ✓ 匹配 [175–211]
  - [p0125](#p0125) “You really do take after Václav” — ✓ 匹配 [69–100]
- Are Pleiades’s Processor and Undertaker the same individual or different squadron captains?（相关：`c005` Pleiades’s Processor，`c006` Undertaker）
  - [p0031](#p0031) “the third squadron’s captain, the Processor operating Personal Name unit Pleiades” — ✓ 匹配 [231–312]
  - [p0180](#p0180) “This is the Spearhead squadron’s captain, Personal Name: Undertaker, speaking.” — ✓ 匹配 [35–113]
- What caused Undertaker’s former Handlers to hear ghosts’ voices or commit suicide?（相关：`c006` Undertaker）
  - [p0111](#p0111) “they claimed they could ‘hear the ghosts’ voices’ and were haunted by them even after retiring from service” — ✓ 匹配 [51–158]
  - [p0110](#p0110) “some have committed suicide after resigning” — ✓ 匹配 [476–519]
- Why did the Empire of Giad fall, and did the Legion turn against it?（相关：`g002` Empire of Giad，`g003` Legion）
  - [p0121](#p0121) “It was uncertain why the Empire fell; did the Legion turn against them, or was there some other reason?” — ✓ 匹配 [315–418]
- Who was the Eighty-Six researcher who worked on the Para-RAID’s fundamental theory, and where are they now?（相关：`c012` the other researcher）
  - [p0157](#p0157) “The other researcher was an Eighty-Six.” — ✓ 匹配 [101–140]
  - [p0157](#p0157) “there was no way of even knowing which internment camp they’d been sent to” — ✓ 匹配 [326–400]
- What did Professor Josef von Penrose connect to during the accident?（相关：`c007` Professor Josef von Penrose）
  - [p0159](#p0159) “Some believed he connected to somewhere that lay beyond the human collective unconscious.” — ✓ 匹配 [326–415]
- Is Theobald definitely the man who came for Annette’s arranged marriage test?（相关：`c002` Annette，`c008` Theobald）
  - [p0169](#p0169) “the guy who came over for my arranged marriage” — ✓ 匹配 [31–77]
  - [p0172](#p0172) “‘To my darling Theobald’” — ✓ 匹配 [167–191]

## 附录：本章原文段落

<a id="p0001"></a>**[p0001]** CHAPTER 1 A BATTLEFIELD WITH ZERO CASUALTIES

<a id="p0002"></a>**[p0002]** There were no casualties on that battlefield.

<a id="p0003"></a>**[p0003]** “—And now, we have an update regarding the war. “A group of the unmanned Imperial weapons known as the Legion have invaded the seventeenth ward today. The force was intercepted, severely crippled, and forced to retreat by the might of our unmanned drones, the Juggernauts, pride and joy of the Republic of San Magnolia. Damage to equipment was light, and no loss of life was reported on our side today yet again.”

<a id="p0004"></a>**[p0004]** The main street of the Republic of San Magnolia’s capital, Liberté et Égalité, was so peaceful and beautiful one would be hard pressed to believe the country had been at war for the past nine years.

<a id="p0005"></a>**[p0005]** Carved white marble graced the facades of the city’s high-rise buildings. The greenery of the roadside trees and the black cast-iron lampposts mingled to create a picturesque contrast with the spring sunlight and the clear blue sky. The cafés on the street corners were populated by students and couples, their naturally silver hair glittering as they laughed loudly.

<a id="p0006"></a>**[p0006]** The city hall’s blue roof was adorned with a flag bearing the visage of the saint of the revolution, Saint Magnolia, and the Republic’s five-colored national flag. Its five colors stood for freedom, equality, brotherhood, justice, and nobility. The main street was paved with vast, delicately carved stones, the result of meticulous urban planning.

<a id="p0007"></a>**[p0007]** A young boy passed by Lena, his silver hair shining like the moon as he laughed, holding his parents’ hands. Dressed so neatly, they were probably going out somewhere. Sparing a final glance at the backs of the happy family, she turned her silver eyes to the street-side television’s holo-screen, the smile fading from her lips.

<a id="p0008"></a>**[p0008]** She was clad in the Republic military’s dark-blue collared uniform for female officers. The sixteen-year-old girl had a snow-white beauty and a certain glasswork delicacy that fit her age—and an elegant demeanor that reflected her upbringing and pedigree. Her softly flowing, silken hair and long eyelashes were a striking silver, and her large, equally silver eyes served as proof of her being not only an Alba, a descendant of the race native to this land since ages past, but also a pureblood Celena, who were considered to be of noble birth.

<a id="p0009"></a>**[p0009]** “Under the capable command of our skilled Handlers, these highly efficient drones allow us to defend the nation while eliminating the need to dispatch precious lives to the front lines. There can be no doubting the usefulness of the Republic’s humane and advanced combat system. The day when the Republic’s righteous ways defeat the fallen Empire’s evil relics will surely come even before the entire Legion shuts down in two years’ time. Hail the Republic of Magnolia. Glory to the five-hued flag.”

<a id="p0010"></a>**[p0010]** Lena’s expression darkened at the sight of the snowy-haired, silver-eyed alabaster newscaster’s brilliant smile. This optimistic, or rather unrealistic, news report had been repeated countless times since the war began, and the majority of civilians didn’t doubt its authenticity. They believed it in spite of the fact that after being driven out of more than half its territory less than a month into the war, the Republic had failed to regain any of it in nine years of fighting.

<a id="p0011"></a>**[p0011]** And all it took was one cursory look around this picturesque main street to notice a certain fact. It was evident in the newscaster, the couples and students in the café, the people passing by, and of course, even Lena herself. The Republic prided itself on being the first modern democracy in the world and proactively welcomed immigrants from other countries. The Republic had been the native land of the Alba since ages past, while other countries were home to people of different colors. All people of color, Colorata, were welcomed equally, be they the dark-as-night Aquila; the golden Aurata, who shone like the sun; the Rubela with their brilliant crimson hair; or the blue-eyed Caerulea.

<a id="p0012"></a>**[p0012]** But right now, if one was to scour the capital’s main street—no, even the city in its entirety—all one would find in the Republic’s eighty-five administrative Sectors would be silver-haired, silver-eyed Alba.

<a id="p0013"></a>**[p0013]** Yes, formally speaking, there were no soldiers considered human or counted among the dead on the battlefield. However…

<a id="p0014"></a>**[p0014]** “…That’s not to say no one died.” One corner of Palace Blancneige, once home to the royal court in days past, now served as the military’s luxurious headquarters. This palace, and the fortification wall that encircled the administrative Sector, the Gran Mule, was Lena’s destination and the center of command for the entirety of the Republic’s military.

<a id="p0015"></a>**[p0015]** There were no soldiers outside the Gran Mule, on the front lines one hundred kilometers away from the fortress walls. Only drones—Juggernauts —fought on the battlefield, and they were commanded from control rooms in the military’s headquarters. Their line of defense, which consisted of over one hundred thousand Juggernauts, with antipersonnel, anti-tank minefields at their back and a surface-to-surface interception artillery cannon, had never been breached. And of course, the forces stationed at the Gran Mule had never seen live combat. Other professions in the military included communications, transport, analysis, tactical planning, and assorted bureaucracy. In other words, not a single soldier in the Republic military had ever known true combat.

<a id="p0016"></a>**[p0016]** Lena frowned, catching the conspicuous stench of alcohol coming from a group of officers that passed her by. They had probably used the control room’s large screen to watch sports or something again. As she aimed a reproachful look at them, her gaze was met with sneering eyes.

<a id="p0017"></a>**[p0017]** “Gentlemen, it looks like our little doll-loving princess has something to say.”

<a id="p0018"></a>**[p0018]** “Whoa, scary, scary. She’s better off shutting herself in her room and playing with her precious drones.”

<a id="p0019"></a>**[p0019]** She wheeled around to look at them, unable to contain her irritation. “Listen, you—” “Morning, Lena.” A voice called out to her from her side, and she turned to find Annette, who had joined the army the same year she had, greeting her. She was a technical lieutenant affiliated with the lab division and a friend of Lena’s since secondary school. As they had both skipped a grade, she was currently Lena’s only friend who was the same age.

<a id="p0020"></a>**[p0020]** “…Good morning, Annette. You’re certainly here early. Don’t you usually oversleep?”

<a id="p0021"></a>**[p0021]** “I’m on my way back from work. Pulled an all-nighter yesterday… Please don’t lump me together with those idiots, okay? You know I’m a workaholic. An issue that could only be resolved by certified genius Technical Lieutenant Henrietta Penrose popped up.”

<a id="p0022"></a>**[p0022]** Annette gave a long, catlike yawn. Her short hair was an Alba’s silver, and her large, hanging eyes were a similar silvery hue. Annette shrugged, sparing a glance in the direction of the group of drunkards that had retreated during the pair’s exchange, as if to say that trying to discipline idiots like them was a waste of time. Lena blushed, realizing from the look in her friend’s elegant eyes that she was trying to stop her from doing just that.

<a id="p0023"></a>**[p0023]** “Oh, right. The alert on your information terminal was on. You should probably take care of that.”

<a id="p0024"></a>**[p0024]** “Oh no… Sorry. Thanks, Annette.” “Don’t mention it. Just try to not get too caught up with the drones, okay?”

<a id="p0025"></a>**[p0025]** Lena turned on her heel, a frown on her face, and after shaking her head once, made her way to her designated command room. The command room was small, half filled by an artificial, mechanical command console, and was an otherwise dark, chilly, and cold space. The silvery walls and floor were dimly lit by the console’s standby-mode hologram.

<a id="p0026"></a>**[p0026]** Taking a seat on the armchair, Lena shifted her argent locks aside and placed a resplendent metal ring—the RAID Device—around her neck with a cold, dignified gaze. Now that the battlefronts were far beyond the walls of the Gran Mule, this cramped room was the sole battlefield one could find in the Republic’s eighty-five Sectors.

<a id="p0027"></a>**[p0027]** “Commence authentication. Major Vladilena Milizé, commanding control officer for the eastern front’s ninth ward, third defensive squadron.”

<a id="p0028"></a>**[p0028]** Having completed its retinal and voice authentication, the control system turned on. Holographic screens flickered on one after another, displaying a dizzying amount of information from countless pieces of observation equipment set across the distant battlefield. The main screen was a digital map that displayed the Republic’s and the enemy’s mobile weapons as blips. The friendly units—in other words, the Juggernauts—were displayed as blue blips, numbering seventy. The third squadron, which was under Lena’s command, had twenty-four units, while the second and fourth squadron had twenty-three each. The red blips that symbolized the enemy units, the Legion, were far too many to count.

<a id="p0029"></a>**[p0029]** “Activate Para-RAID. Set Resonance target, information-processing unit Pleiades.”

<a id="p0030"></a>**[p0030]** The blue-crystal portion of the RAID Device, which was set against the nape of Lena’s neck, suddenly prickled with heat. It wasn’t actual, physical heat but an illusory heat felt by her nerve cells as they were stimulated by the Sensory Resonance. The activated pseudo-nerve-cell crystal served as an information-processing unit and stimulated a certain part of the brain. Perhaps that part held potential to be unlocked by humanity’s evolution, or perhaps it was an unused section, left behind and forgotten by humankind as it evolved ages ago. Whatever the case, using it unlocked a deep, nigh-vestigial function of the brain known as the Night Head.

<a id="p0031"></a>**[p0031]** Lena passed through a “path,” diving into a place far deeper than her consciousness and even her subconscious. The “collective unconscious” of humankind, shared by every member of the human race. Lena linked her consciousness with the third squadron’s captain, the Processor operating Personal Name unit Pleiades via the sea of the unconscious. Pleiades’s and Lena’s sensory information was linked and shared.

<a id="p0032"></a>**[p0032]** “Handler One to Pleiades—Resonance complete. I look forward to working with you today,” she said gently, and the “voice” of a young man, presumably a year or two older than she was, replied.

<a id="p0033"></a>**[p0033]** “Pleiades to Handler One. Resonance is loud and clear.”

<a id="p0034"></a>**[p0034]** The voice was laced with irony. Lena was all alone in the command room, so it wasn’t the someone else with her. It was the voice of Pleiades’s Processor, being transmitted to her through their now-shared sense of hearing.

<a id="p0035"></a>**[p0035]** A voice. Having been built in a hurry during wartime, Juggernauts weren’t constructed to be able to communicate orally, and they weren’t programmed to have advanced cognitive abilities that would allow them to think or feel. The Para-RAID—Sensory Resonance—linked consciousness via the human collective unconscious; the defense lines’ minefield, despite the enemy using armored units, was set with antipersonnel mines.

<a id="p0036"></a>**[p0036]** The secret behind the front lines where drones fought one another, the battlefield with zero casualties.

<a id="p0037"></a>**[p0037]** “Your polite greetings to us subhuman Eighty-Six are much appreciated, Alba.”

<a id="p0038"></a>**[p0038]** Eighty-Six. As the continent was being swept over by the Legion, the last remaining paradise for the Republic’s citizens was the eighty-five Sectors. The Eighty-Sixth Sector was designated a no-man’s-land, populated by pigs in human form. Despite being born civilians of the Republic, they were decreed to be subhuman, inferior life-forms by the Republic. It was a derogatory name for those Colorata cast outside the Gran Mule to live in internment camps on the front lines.

<a id="p0039"></a>**[p0039]** Nine years earlier, year 358 of the Republic calendar, year 2136 of the global calendar.

<a id="p0040"></a>**[p0040]** The Republic’s eastern neighbor and superpower of the northern continent, the Empire of Giad, declared war on all its neighboring countries and began attacking with an army of the world’s first completely autonomous unmanned combat drone, Legion.

<a id="p0041"></a>**[p0041]** Faced with the Empire’s overwhelming military strength, the Republic Armed Forces were decimated within half a month. As what was left of the army gathered its remaining forces to stall the invasion via hopeless delay tactics, the Republic’s government made two decisions.

<a id="p0042"></a>**[p0042]** The first was the evacuation of all the Republic’s citizens to the eighty-fifth administrative Sector. The second was Presidential Order #6609. The Special Wartime Peace Preservation Act. This law acknowledged all persons of Colorata descent within the borders of the Republic as inimical characters and supporters of the Empire and allowed the stripping of their civilian rights. They were designated as targets of monitoring and isolated in internment camps outside the eighty-five Sectors.

<a id="p0043"></a>**[p0043]** This act was, of course, in violation of the Republic’s constitution and the spirit of the five-hued flag. The law also did not include Alba, who formerly lived in the Empire. Neither did it spare Colorata who were not originally from the Empire. It was a policy of blatant racism and discrimination.

<a id="p0044"></a>**[p0044]** The Colorata were opposed to the law, of course, but their opposition was silenced by violence at the hands of the government. Some Alba, however few, also cried out against the law, but the majority accepted it. The eighty-five Sectors were far too small to accommodate the sheer number of civilians, and there was nowhere near enough food, land, or labor for everyone. False rumors were spread that the Republic’s defeat in the war came as a result of the Colorata’s spying. Those rumors were far easier for the civilians to accept than coming to terms with their country’s technological inferiority.

<a id="p0045"></a>**[p0045]** But more than anything, in a situation where they were surrounded and isolated by enemies, they needed something, someone, to take their frustrations out on. This justification by way of eugenics spread quickly among the populace. The Alba, who founded the country that stood as the foremost advocate of democracy—the greatest, most humane of all forms of government—were the superior race. By contrast, the Colorata, with their outdated, cruel, and inhumane imperialism, were an inferior species— barbaric and foolish subhumans, pigs in human form and the result of an evolutionary blunder.

<a id="p0046"></a>**[p0046]** Thus, all Colorata in the Republic were banished to internment camps where they were forced into labor and conscripted for the sake of constructing the Gran Mule. Their properties and belongings were requisitioned by the government to fund the construction of the wall and the war effort, and the Alba civilians who were spared from conscription, labor, and wartime taxes all praised the government’s humane methodology.

<a id="p0047"></a>**[p0047]** The Alba mocked the Colorata as a lesser species, calling them the Eighty-Six. This discriminatory approach ultimately manifested two years later with the introduction of drones manned by living soldiers—and all those soldiers were of the Eighty-Six. Despite pouring all their efforts into producing a Republic-made unmanned drone, no attempt ever achieved the level where it could withstand live combat. But there was no way the superior Alba could admit to failing to produce such a machine when the inferior Empire could.

<a id="p0048"></a>**[p0048]** Since the Eighty-Six were not considered human, having one pilot the machine would categorize it not as a mounted craft but as an unmanned drone.

<a id="p0049"></a>**[p0049]** The Republic Militarized Autonomous Drone known as the Juggernaut, manufactured by Republic Military Industries (RMI), was lauded by the civilians upon its release as an innovative, cutting-edge, and humane weapon system that minimized human casualties to zero. The Eighty-Six who served as pilots were designated information-processing units— Processors—making the Juggernaut an Operated Drone.

<a id="p0050"></a>**[p0050]** The year 367 of the Republic calendar. Yet another day dawned when soldiers, who were treated as nothing more than mechanical parts, set out to suffer deaths that would not be counted as deaths, on a battlefield without casualties.

<a id="p0051"></a>**[p0051]** Confirming that the Legion’s red blips were retreating east—into the depths of their territory—Lena finally felt the tension begin to leave her body. In exchange for this retreat, her third squadron lost seven units. A bitter taste filled her mouth. Seven Juggernauts detonated, exploding along with the Processors who piloted them. None survived.

<a id="p0052"></a>**[p0052]** Juggernaut—the name the so-called intellectual developers gave to this machine, drawing on the name of a god from a foreign land’s mythos. Countless people would gather before this tank in search of salvation and would be run over by its wheels and crushed to death in its wake.

<a id="p0053"></a>**[p0053]** “…Handler One to Pleiades. We’ve confirmed the enemy forces’ retreat.” She communicated this to Pleiades’s Processor—the Eighty-Six pilot who agreed to serve on the field of battle for five years in exchange for the restoration of his family’s civil rights—via Para-RAID.

<a id="p0054"></a>**[p0054]** Sensory Resonance allowed them to hear each other’s voices as well as the sounds of their surroundings. It was truly a groundbreaking means of communication that rendered radio transmissions (which were susceptible to interference by distance, weather conditions, and terrain—not to mention the electromagnetic jamming of the Eintagsfliege clouds) completely obsolete.

<a id="p0055"></a>**[p0055]** Theoretically, all five senses could be linked via Para-RAID, but typically, users chose to link only their sense of hearing. The amount of data shared by linking eyesight via Para-RAID was often overwhelming and could result in sensory overload, risking serious damage to the user. Hearing, on the other hand, gave one a solid grasp of the situation on the other side with minimal data. In terms of actual experience, it wasn’t much different from communication via radio or telephone, but there were comparatively fewer disturbances.

<a id="p0056"></a>**[p0056]** Lena believed those weren’t the only reasons. Refusing to link eyesight spared the Handler from having to see many things: the awe-inspiring sight of the enemy charging toward you, the sight of one’s comrades being ruthlessly blown to bits in every direction, the color of viscera and blood spilling from one’s own eviscerated body.

<a id="p0057"></a>**[p0057]** “The fourth squadron will take over lookout duties. Third squadron, please return to base.”

<a id="p0058"></a>**[p0058]** “Acknowledged, Pleiades… Hope you enjoyed watching us pigs squabble through your little telescope, Handler One.”

<a id="p0059"></a>**[p0059]** The scathing irony that never left his voice from start to finish made Lena look at the floor. She knew they couldn’t help but hate her. She was an Alba—and one of their oppressors. And just like he said, keeping watch over them was part of her role as Handler.

<a id="p0060"></a>**[p0060]** “Good job today, Pleiades. And to all other units, too, and the seven who were lost… I’m so, so sorry.”

<a id="p0061"></a>**[p0061]** “…”

<a id="p0062"></a>**[p0062]** A certain coldness, like that of a sword being drawn from its scabbard, mixed into the silence on the other side of the Resonance. The Para-RAID linked only their hearing, but since the Resonance was conducted via their consciousness, feelings that would normally come across only in face-to-face conversations were also transmitted.

<a id="p0063"></a>**[p0063]** “…Thank you for all the kind words you always offer us, Handler One.”

<a id="p0064"></a>**[p0064]** Cold contempt and hatred were sprinkled into those words. But there was something to the coldness that went beyond the kind of obvious hatred and indignation one would feel toward their oppressor. Something that left Lena confused and bewildered.

<a id="p0065"></a>**[p0065]** The following morning’s news once again spoke of how vast the enemy’s losses were, how light the damage to the Republic’s side was, and how there were—as always—no casualties. The announcer once again praised the Republic’s cutting edge and humane tactics, how the enemy’s defeat must be close at hand, and so on and so forth. Lena sometimes wondered whether the news was actually a recording being broadcast over and over. This was a government-sponsored broadcast, with an emblem of a sword and shattered chains in the background. These stood for the overthrowing of sovereign rule and the fall of oppression and were the symbol of Saint Magnolia, patron saint of the revolution.

<a id="p0066"></a>**[p0066]** “…In preparation for the cessation of hostilities in two years’ time, the government has decided to gradually reduce the military budget. As a precursor to that, the seventeenth ward of the southern front will be abolished, and all forces stationed there dissolved and discharged—”

<a id="p0067"></a>**[p0067]** Lena sighed. They probably surrendered the seventeenth ward. This certainly wasn’t the kind of news they could afford to simply gloss over. Not only had they lost territory, they were giving up on trying to reclaim it and choosing to disarm themselves on top of that. The government had used up all the Eighty-Six properties a long time ago, and now the voices of the civilians demanding they reduce the vast war budget and disarm in favor of welfare and public works were becoming gradually harder to ignore.

<a id="p0068"></a>**[p0068]** Sitting across from her, dressed in an antiquated gown, Lena’s mother opened her perfectly rouged lips to speak.

<a id="p0069"></a>**[p0069]** “…What’s the matter, Lena? Put away your troubles and have something to eat.”

<a id="p0070"></a>**[p0070]** The dining room table was set with breakfast, but the majority of it was factory-made synthetic food. Having lost half its land, the Republic was running out of space as its population increased by 80 percent—with the exception of the Eighty-Six. And the eighty-five Sectors didn’t have the farmland required to support the population. They were also cut off from other foreign countries by the Legion’s Eintagsfliege jamming, which meant that trading, diplomatic relationships, or even confirming whether any such countries still existed was impossible.

<a id="p0071"></a>**[p0071]** Lena took a sip of tea that was different from the tea she hazily remembered from the past and cut a piece of synthetic meat, made from wheat proteins and created to replicate natural meat’s appearance and flavor. The only natural thing about her meal was the compote she added to her tea, made from raspberries they grew in the garden. But even this was a commodity not seen in the Republic’s average household, which didn’t even have room for a flowerpot, much less a garden, making it fairly valuable.

<a id="p0072"></a>**[p0072]** Her mother smiled. “Lena, isn’t it about time you quit the army and find a groom from a good family?”

<a id="p0073"></a>**[p0073]** Lena sighed internally. This conversation was repeated word for word every day, same as the news broadcast. Pedigree. Status. Standing. Lineage. Superior bloodline. This silk dress, which became antiquated and obsolete the moment you stepped outside. This mansion, built in the days when the Milizé household was still considered nobility. Preserved relics of a blessed era long gone, standing frozen in time, enveloping themselves in sweet dreams and refusing to look outside.

<a id="p0074"></a>**[p0074]** “The Legion and the Eighty-Six are hardly matters the daughter of the great Milizé household should concern herself with. I know your late father was a soldier, but the war is behind us now.”

<a id="p0075"></a>**[p0075]** How could the war be behind them if they were in the middle of fighting the Legion even now? The battlefield was just far and out of sight, and those who went to war never returned to speak of it. As far as the civilians were concerned, the war was nothing more than a collection of fictional events in a movie, with no sense of reality or involvement on their part.

<a id="p0076"></a>**[p0076]** “Protecting the motherland is a Republic citizen’s duty and pride, Mother. And please don’t call them Eighty-Six. They’re respectable citizens of the Republic, same as you and me.”

<a id="p0077"></a>**[p0077]** A wrinkle ran across her mother’s thin, refined nose. “How can you consider them members of the Republic when they’re stained with those filthy colors? Honestly, even if you must feed livestock to have it do your bidding, what is the government thinking, letting those animals set foot on Republic soil?”

<a id="p0078"></a>**[p0078]** The Eighty-Six who agreed to engage in combat were granted the restoration of civil rights for themselves and their families. To protect them from the severe persecution and discrimination of the eighty-five Sectors, their whereabouts were kept confidential, but it’d been nine years since the beginning of the war. Surely some of them had returned to live in their old homes by now.

<a id="p0079"></a>**[p0079]** This was the just reward they received for their dedication to the state. Sadly, those in power could not see the justification for such a reward and merely shook their heads at the deplorable state of affairs.

<a id="p0080"></a>**[p0080]** “Ah, how dreadful. It was only ten years ago that they were loitering about Liberté et Égalité as if they owned the place. And to think, they may actually return… To what extent will our Republic’s freedom and equality have to be sullied before they’re satisfied…?”

<a id="p0081"></a>**[p0081]** “…If anything is sullying the ideas of freedom and equality, Mother, it would be the words you just spoke.”

<a id="p0082"></a>**[p0082]** “I beg your pardon?” Seeing her mother’s astonished expression, Lena truly did sigh this time. She just didn’t understand. She honestly, truly, didn’t understand. And it wasn’t just her mother. Civilians throughout the Republic took pride in the five-hued flag and its values of freedom, equality, brotherhood, justice, and nobility. They believed they had learned from history and loathed tyranny, resented exploitation, scorned discrimination, and avoided murder and atrocities, seeing these as the devil’s deeds.

<a id="p0083"></a>**[p0083]** But they simply did not understand that the Republic was committing those very same atrocities right now. And if you were to attempt to point that out, they would merely look at you with pity and ask, “Can’t you tell pigs apart from people?” Lena bit her lip. Words truly were convenient. They could gloss over the truth so easily. All it took was a simple rewrite of a name tag, and you could reduce a human to a pig.

<a id="p0084"></a>**[p0084]** Her mother looked at her with a troubled expression but eventually smiled as if she’d come to a realization.

<a id="p0085"></a>**[p0085]** “Your father took pity on the livestock, and now you’re taking after him. Is that it?”

<a id="p0086"></a>**[p0086]** “N-no, that’s not…” Lena did deeply respect her father, who’d greatly objected to the Eighty-Six’s internment until the very end. But she didn’t quite intend to follow in his footsteps. Because she could still remember that silhouette of a quadruped spider, the crest of a headless skeletal knight etched upon its armor, the extended hand that had saved her from disaster, those shades of brilliant red and jet-black he’d borne since birth.

<a id="p0087"></a>**[p0087]** We are Republic citizens. We were born in this country and raised in this country. And that’s why…

<a id="p0088"></a>**[p0088]** Her mother’s presumptuous voice pulled Lena out of her memories. “But you should know, Lena. You should know to treat livestock as livestock. You simply cannot get those barbarian Eighty-Six to understand human ideals and nobility. It only makes sense that we confine them to their cages and manage their lives.”

<a id="p0089"></a>**[p0089]** Lena wordlessly finished her breakfast, wiped her mouth with a napkin, and stood up.

<a id="p0090"></a>**[p0090]** “I’m off, Mother.” “You’re changing my assigned squadron…?”

<a id="p0091"></a>**[p0091]** The golden wallpaper, streaked with dark-red stripes, gave the division commander’s office a profound, dignified atmosphere. Lena blinked her silver eyes, her gaze fixed on the notice of personnel change she’d received from the division commander seated behind the antiquated desk, Commodore Karlstahl.

<a id="p0092"></a>**[p0092]** Squadron reorganizations and, by extension, changes of a Handler’s assigned squadron actually happened fairly often. As they participated in battle after battle, squadrons gradually took increased losses to the point where continued combat became impossible. As such, squadrons were routinely integrated into one another, reorganized, abolished, and formed anew. Even transfers owing to the complete obliteration of a squadron were common, albeit a circumstance Lena had neither experienced personally nor had any desire to.

<a id="p0093"></a>**[p0093]** The Legion were simply that strong. Having developed them with full ferocity and technological superiority, the militant Giadian Empire spared no expense when outfitting the Legion with the most advanced weapons and allowing them the utmost mobility possible, as well as capacity for autonomous thought so advanced it was hard to believe it was a product of this age’s technology. On top of that, since they were truly unmanned drones, the Legion never tired, never disobeyed orders, and never knew fear. And no matter how many were destroyed, fully automated production and repair factories lay scattered across the depths of their territories, rolling out new units like the black smoke spewing from their chimneys.

<a id="p0094"></a>**[p0094]** Contrary to what the civilians believed, the Juggernaut was far inferior to the Legion in terms of performance, and the idea of getting out of a fight with the Legion with minor losses was unthinkable. Even if the Republic did inflict great damage on the Legion, they always returned in equal numbers, and the most the Republic could do was maintain a defensive line.

<a id="p0095"></a>**[p0095]** However, the squadron Lena was currently in charge of hadn’t suffered that many losses.

<a id="p0096"></a>**[p0096]** Karlstahl’s scarred cheeks slackened into a smile. His beard gave off a feeling of gentle dignity, and his frame was tall and broad-shouldered.

<a id="p0097"></a>**[p0097]** “Your squadron isn’t getting reorganized or integrated. The truth is another squadron’s Handler recently resigned, and we need to elect a replacement Handler from another squadron as quickly as possible.”

<a id="p0098"></a>**[p0098]** “Is it a defensive unit for some important location?” Which would mean it was a unit that couldn’t remain on standby until a replacement Handler was found.

<a id="p0099"></a>**[p0099]** “Indeed. It’s the eastern front’s first ward’s first defensive squadron, also known as the Spearhead squadron. It’s a unit that consists of veterans from the eastern front… You could call it an elite unit.”

<a id="p0100"></a>**[p0100]** That made Lena’s beautiful features contort into a frown. The first ward was certainly an important location; it was an imperative defensive position where the Legion’s advance was the fiercest. And the first defensive squadron was a significant unit that was single-handedly responsible for the first ward’s defense. The duties placed on it, such as night patrol and serving as support, were entirely different compared to the second, third, and fourth squadrons, which served as backup in case the first wasn’t able to sortie.

<a id="p0101"></a>**[p0101]** “I think this is too much responsibility to place on a novice like me, sir…” Karlstahl smiled wryly. “Is that something a talented, aspiring officer who was the youngest and first to be promoted to major out of ninety-one alumni should say? Being too modest can buy you others’ ire, Lena.”

<a id="p0102"></a>**[p0102]** “I-I’m sorry, Uncle Jérôme.” Karlstahl referred to Lena by her first name, and she responded by lowering her head in a manner unlike that of a subordinate. Karlstahl had been best friends with Lena’s late father, who had fought alongside him nine years ago as part of the now demolished Republic Armed Forces. The two were among its sole survivors. He would come to visit often when Lena was small and play with her, and after her father’s passing, he helped arrange the funeral, as well as support Lena and her family in various ways.

<a id="p0103"></a>**[p0103]** “I’ll be frank with you… We don’t have any other candidates for the Spearhead squadron’s Handler.”

<a id="p0104"></a>**[p0104]** “Didn’t you say they were an elite unit? I would think being put in charge of that would be a great honor for any Republic soldier.”

<a id="p0105"></a>**[p0105]** Not all Handlers took their jobs seriously, however. Some would watch television or play video games in the command room or leave it unattended altogether. Others would give their Processors terrible orders or not provide them information at all and watch as they died, as if it were just some movie. Others would place bets with their colleagues on whose squadron would get wiped out first. Lena knew that, of course. If anything, those who took their jobs seriously were the stark minority, but that was beside the point.

<a id="p0106"></a>**[p0106]** “Ah, well, it is an elite unit, but…” Karlstahl seemed hesitant for a second. “It’s the Spearhead squadron’s captain unit, Personal Name: Undertaker. He has something of, shall we say, a history.”

<a id="p0107"></a>**[p0107]** Undertaker. What an odd name. “The Handlers who know him seem to call him the Reaper and are all frightened of him… It seems he has a tendency to…break his Handlers.”

<a id="p0108"></a>**[p0108]** “Huh?”

<a id="p0109"></a>**[p0109]** Lena replied in surprise despite herself. If it had been the other way around, that wouldn’t have been so odd, but a Processor breaking a Handler?

<a id="p0110"></a>**[p0110]** How? “Are you sure this isn’t some kind of ghost story, sir?” “I guarantee you I haven’t had the luxury to call my subordinates over to discuss gossip, my dear… It’s a fact that an unusually high number of Handlers who were in charge of Undertaker’s squadrons have put in requests to change their assignments or requested to resign from service altogether. Some have requested transfers immediately after their first sortie, and while we’re unsure as to whether it’s related, some have committed suicide after resigning.”

<a id="p0111"></a>**[p0111]** “Suicide, sir…?” “It’s rather hard to believe, but…they claimed they could ‘hear the ghosts’ voices’ and were haunted by them even after retiring from service.”

<a id="p0112"></a>**[p0112]** “…” It didn’t sound like anything but a ghost story, after all. Karlstahl cocked his head, anxiously trying to discern what Lena was thinking.

<a id="p0113"></a>**[p0113]** “If you’re against the idea, feel free to refuse, Lena. You can stay in command of your current squadron, and as I’ve said, Spearhead is a gathering of veterans. From what I hear, Resonating with them during sorties isn’t advised, so we could very well leave command to those on the field and provide minimal monitoring—”

<a id="p0114"></a>**[p0114]** Lena pursed her lips tensely. “I’ll do it. I’ll put all my efforts into serving as the Spearhead squadron’s commanding officer.”

<a id="p0115"></a>**[p0115]** Protecting the motherland was a Republic citizen’s duty and pride. Being put in charge of a unit that stood as the vanguard of the war effort was all she could ask for, and letting this opportunity pass by was unacceptable.

<a id="p0116"></a>**[p0116]** Karlstahl smiled at her fondly. Really, this girl is simply too much… “You can do the absolute minimum. There’s no need to do anything unnecessary… And also, refrain from interacting with the Processors too much.”

<a id="p0117"></a>**[p0117]** “Knowing one’s subordinates is part of a commanding officer’s duties. So long as they don’t reject me, I will make every effort to interact with them.”

<a id="p0118"></a>**[p0118]** “Good grief…” Karlstahl sighed with a gentle smile. He opened the desk’s drawer and retrieved a bundle of documents.

<a id="p0119"></a>**[p0119]** “And while we’re on the subject of fault finding, I’ve got something else to say. For heaven’s sake, stop recording the number of casualties in your reports. There are officially no people on the battlefield, so we can’t accept documents regarding data that doesn’t exist… Even if you try to protest like this, there’s no one who will take this matter to heart anymore.”

<a id="p0120"></a>**[p0120]** “Be that as it may, I cannot simply ignore this… There’s no basis for confining the Colorata anymore.”

<a id="p0121"></a>**[p0121]** The Empire of Giad took the continent by storm with their army of Legion. But for some reason, it seemed to have fallen into ruin four years ago. The Empire transmissions the Republic was able to intercept in between waves of Eintagsfliege jamming suddenly ceased, and they had been unable to intercept them since. It was uncertain why the Empire fell; did the Legion turn against them, or was there some other reason? Whatever the case, one fact was abundantly clear: The Empire had certainly fallen.

<a id="p0122"></a>**[p0122]** The Eighty-Six were detained for being “progeny of the Empire,” but now that the Empire was gone, there was no justification for their continued internment. However, having tasted the perks of their blatant discrimination, the Republic’s civilians were loath to change their ways. Trampling others granted them the illusion of superiority, and having a group to oppress made them feel like they were the victors. Having been trapped, humiliated, and thrust into a state of emergency by the Empire and its superior weaponry, this was merely a form of escapism that allowed them to delude themselves, rather than confront the issue.

<a id="p0123"></a>**[p0123]** “Being tolerant of such wrongs is tantamount to supporting them. Doing this isn’t something that should be allowed in the—”

<a id="p0124"></a>**[p0124]** “Lena.” That gentle invocation made Lena hold her tongue. “Your pursuit of ideals is a bit too spirited, regardless of whether the ideals are your own or someone else’s. Ideals are precious precisely because they are unreachable.”

<a id="p0125"></a>**[p0125]** “…But…” Karlstahl’s silver eyes wavered with bittersweet nostalgia. “You really do take after Václav… Now then, Major Vladilena Milizé. I hereby appoint you to the role of commanding officer for the eastern front’s first ward’s first defensive squadron, effective as of today. I expect you to do your finest.”

<a id="p0126"></a>**[p0126]** “Thank you very much, sir.” “…So you accepted the offer in the end? You really are a weirdo, Lena.”

<a id="p0127"></a>**[p0127]** Taking command of a new squadron meant quite a number of things would have to be changed as well, and one of those things was the target data for her Para-RAID. Annette was the officer in charge of the Para-RAID development team, so all requests regarding adjusting Lena’s Sensory Resonance settings were handled by her. She also suggested they may as well have Lena come in for a medical inspection while they were at it, and Lena was in the middle of changing back into her uniform when Annette chastised her.

<a id="p0128"></a>**[p0128]** After putting the patient gown neatly on a coat hanger, Lena replied to Annette from the other side of the medical room’s reinforced glass window, still buttoning her blouse. The medical ward’s building had once been a royal villa during the monarchy age, so its exterior was that of a chic, classy Middle Ages estate. But on the inside, it had a certain tasteless, futuristic sort of design, defined by metal and glass panes that gave off a robotic, inorganic feeling. One of the glass screens had a video of tropical fish and coral reefs projected onto it.

<a id="p0129"></a>**[p0129]** “I mean, it’s just a ghost story, Annette. An excuse soldiers cooked up to skip work.”

<a id="p0130"></a>**[p0130]** Fastening both her stockings up with her garters, Lena felt her lips loosen with a smile. She did her periodic Para-RAID medical inspections regularly, so there was no need for Annette to worry. But she was a busybody, after all…

<a id="p0131"></a>**[p0131]** “The part about some of them committing suicide is true, though.” Sitting on the other side of the glass wall, Annette casually added this tidbit while inputting the new settings into Lena’s RAID Device and sipping coffee—or rather, some muddy substance that was probably supposed to resemble coffee—from her mug.

<a id="p0132"></a>**[p0132]** “I don’t buy the whole ghost thing. The old guys probably made that up so they’d have something to gossip about. But it’s true. One blew his own head off with a shotgun.”

<a id="p0133"></a>**[p0133]** Having put on her skirt and jacket, Lena turned around, straightening her collar. She brushed back the silver hair that spilled over her shoulders when she bent forward.

<a id="p0134"></a>**[p0134]** “Really?” “We got a request to check that it wasn’t some Para-RAID malfunction. Resignations aside, word tends to get out when someone kills himself.”

<a id="p0135"></a>**[p0135]** “And what were the results?”

<a id="p0136"></a>**[p0136]** Annette shrugged casually. “Who knows.” “Wh-what do you mean, who knows…?” “What kind of details am I supposed to gather when the subject’s dead? No abnormalities were detected in the RAID Device, and that’s it. I did tell them that if they want me to look any deeper, they should bring over that Processor. Undertaker, I think he’s called? But the boneheads over at Transport starting spouting dumb stuff like ‘We don’t have room for pigs on our flights.’”

<a id="p0137"></a>**[p0137]** Annette crossed her arms while leaning against the chair’s backrest and snorted indignantly. This attitude always spoiled her boyish good looks.

<a id="p0138"></a>**[p0138]** “If they’d have brought him over, I’d have been able to pick apart his brain and investigate. Dammit.”

<a id="p0139"></a>**[p0139]** Lena frowned at the ominous remark. Annette wasn’t serious, of course, but it was still rather dark.

<a id="p0140"></a>**[p0140]** “…Hmm, how did you hear about the Processor…?” “Heard about him from the MPs. They let me have a look at the report, but it really was just a bunch of official data. They asked me if anything came to mind, and that was it. No idea if he actually had anything to do with it.”

<a id="p0141"></a>**[p0141]** Having said this, Annette smirked wryly. “Apparently, when they told him his Handler died, all he said was ‘Is that so?’ Like he had no idea what they wanted him to make of it. Guess it makes sense for an Eighty-Six to feel that way, though. Even if you tell them their commanding officer died, they won’t really care.”

<a id="p0142"></a>**[p0142]** “…” When she saw Lena’s silent expression, the smile disappeared from Annette’s face.

<a id="p0143"></a>**[p0143]** “…Lena, you should transfer over to the lab after all.” “?” Annette watched Lena’s baffled expression with lustrous, feline eyes. “The way things are now, the military’s nothing more than unemployment relief. Everywhere but the lab is full of idiots from the higher Sectors who couldn’t hold a job.”

<a id="p0144"></a>**[p0144]** The Republic’s current administrative center was the First Sector, and it was at the heart of it all. The other Sectors spread out from its four sides in a rectangular fashion, designated numbers by order of closeness. The higher a Sector’s number, the worse its residential environment, public safety, and standards of education became, and the higher its unemployment rate grew.

<a id="p0145"></a>**[p0145]** “What are you going to do in two years once the Legion aren’t an issue anymore? Having ‘former military personnel’ on your résumé isn’t gonna turn any heads during peacetime.”

<a id="p0146"></a>**[p0146]** Lena smiled. In two years’ time, all Legion units would shut down. That was a fact the Republic discerned by inspecting several Legion units they’d seized. The Legion’s central processors had a fixed life span programmed into them: fifty thousand hours of operation time per version. In other words, just shy of six years. The Empire likely added this design element as a fail-safe to ensure the Legion didn’t go berserk and turn on them.

<a id="p0147"></a>**[p0147]** And since the Empire was presumably destroyed four years ago, all of the Legion’s central processors should break down and cease operation in two years’ time. And indeed, the number of Legion they had detected on the battlefield had been gradually decreasing over the years. Units that hadn’t received the latest updates had begun shutting down.

<a id="p0148"></a>**[p0148]** “Thanks for the offer. But right now, we are at war.” “Yeah, but this doesn’t have to be your job.” Annette wasn’t willing to back down. Completing the input job, she flicked the holo-screen aside, bent forward, and began venting her frustrations in an agitated, bitter voice.

<a id="p0149"></a>**[p0149]** “Whatever the truth is, that’s one messed up Processor we’re talking about here. Who knows what to expect from him… And besides, there’s no telling if the Para-RAID is actually safe.”

<a id="p0150"></a>**[p0150]** Lena’s eyes widened. “Wasn’t it proven that the Para-RAID is perfectly safe?” Annette had apparently just let slip something she shouldn’t have. She lowered her voice, continuing to speak with a guilty expression that made it clear she’d just gotten herself in trouble.

<a id="p0151"></a>**[p0151]** “I mean, don’t you know how this country works, Lena? Even if they say that’s how it is publicly, it doesn’t mean it’s actually true.”

<a id="p0152"></a>**[p0152]** The Republic prided itself on being a superior race and on the country’s technology being infallible. Even if there were any flaws, they could never be made public. This held true for the Para-RAID…and just as true for the Juggernauts.

<a id="p0153"></a>**[p0153]** “They actually discovered this technology by inspecting people with, well, extrasensory perception. That’s how they figured out what part of the brain to stimulate…which is what this thing does.”

<a id="p0154"></a>**[p0154]** She poked the RAID Device in her hand: a blue crystal and a delicate silver frame. The crystal was currently connected by several wires to an information terminal, as the information inside it was being overwritten.

<a id="p0155"></a>**[p0155]** “Those Espers could Resonate with other family members, so the Handler and Processor devices carry quasi-genetic information that identifies the users as relatives on the second degree. We still don’t know how the Resonance actually works.”

<a id="p0156"></a>**[p0156]** “But…wasn’t this your father’s research?” “It was collaborative research. The fundamental theory and hypothesis were all the work of other researchers. Dad was just in charge of preparing the lab conditions and replicating the phenomenon with the recruited test subjects.”

<a id="p0157"></a>**[p0157]** “So you just need to ask the other researcher.” A cold smile played over Annette’s face. “You can’t. The other researcher was an Eighty-Six.” The Eighty-Six, who were considered subhuman, didn’t have their names recorded. When they were taken into custody, they each received a number as their sole identifier. At this point, there was no way of even knowing which internment camp they’d been sent to.

<a id="p0158"></a>**[p0158]** “The RAID Device has a safety lock on it now, but if anyone was to try to Resonate with several people’s sense of vision, their brain would fry itself from the informational overload, and if you stay Resonated for too long at maximum synchronization rate, it’s possible for your ego to completely collapse. You stay too ‘stimulated’ to be able to come back… You know about my dad’s accident, right?”

<a id="p0159"></a>**[p0159]** “…” Annette’s father, Professor Josef von Penrose, was involved in an accident during an experiment that drove him mad and ultimately killed him. It happened shortly after the completion of the Sensory Resonance theory and the RAID Device. The RAID Device’s synchronization rate was accidently set to the theoretical maximum. Some believed he connected to somewhere that lay beyond the human collective unconscious. If humankind as a whole was an individual, that place was the collective—what was presumed to be the collective unconscious of the world itself.

<a id="p0160"></a>**[p0160]** “So like I said, there’s no telling what might happen if you use the Para-RAID too much… I don’t give a rat’s ass what happens to a bunch of Eighty-Six, but if anything happened to you, I don’t know what I’d do…”

<a id="p0161"></a>**[p0161]** Lena grimaced grumpily despite herself. She realized Annette was genuinely concerned for her, but still…

<a id="p0162"></a>**[p0162]** “But that’s…that’s just cowardice.” Annette waved her hand as if to say she’d grown tired of the conversation.

<a id="p0163"></a>**[p0163]** “Yeah, yeah. I swear, you’re a weirdo…” An awkward silence filled both sides of the room parted by the glass wall. As if to dispel that, Annette smiled mischievously.

<a id="p0164"></a>**[p0164]** “While we’re on the topic of things that make you act weird… Lena, you up for some chiffon cake? It’s my latest work. Made from real eggs.”

<a id="p0165"></a>**[p0165]** “Huh?” Annette had to stop herself from laughing out loud as Lena looked up at her, an imaginary pair of cat ears perking up in attention. Lena was as much a girl as any other young lady her age, after all. Sweet things captured her attention in a heartbeat, and a chiffon cake made from real egg whites was a rare commodity in the Republic at present, due to the lack of available space or time to construct poultry farms. Raising chickens in her estate’s garden was the kind of precious luxury only the daughter of the Penrose family, formerly a noble house, could afford.

<a id="p0166"></a>**[p0166]** However…

<a id="p0167"></a>**[p0167]** “Hmm… It won’t taste like cheese even though you didn’t put cheese in it, or be all charred and smoky, or look like a frog, will it…?”

<a id="p0168"></a>**[p0168]** These were the impressions of someone who had tasted the cream puffs Annette had made once. That last comment was an abbreviated version of “the bulging, run-over corpse of a toad.” Putting aside its shape, Annette had somehow managed to replicate a toad’s color to a startling degree of accuracy.

<a id="p0169"></a>**[p0169]** “This one’s safe to eat. I had the guy who came over for my arranged marriage test them.”

<a id="p0170"></a>**[p0170]** Although he’d fainted, frothing at the mouth after the fifth prototype chocolate.

<a id="p0171"></a>**[p0171]** “Then I guess that’s fine… But even if you don’t like him, be sure to give him some chocolate that’s actually safe to eat, okay?”

<a id="p0172"></a>**[p0172]** “Of course I will. I even wrapped it up all cute-like, with pink wrapping paper and a ribbon and everything. Even put a message card with a kiss mark on it that says, ‘To my darling Theobald’… Left it in the mailbox of the apartment he’s renting with his mistress.”

<a id="p0173"></a>**[p0173]** It took Lena a while to decide whether she should feel bad for him or not. Having returned home, Lena attached the RAID Device—which had finished having its data rewritten while she’d been chatting with Annette over a chiffon cake and some tea—to her neck. It was in the shape of an elegant silver choker, engraved with a subtle Alba ornamental pattern. Small, sparkling beads surrounded the quasi-nerve crystal, making it hard to believe this small choker served the same function as a military-grade communication headset.

<a id="p0174"></a>**[p0174]** Her talk with Annette this afternoon suddenly came to mind. The Reaper. The Eighty-Six who drove people to suicide, who didn’t flinch from the prospect of death.

<a id="p0175"></a>**[p0175]** What kind of person was he? Does he…hate us, after all? Lena shook her head once and took a deep breath. All right. “—Activate.” She booted up the Para-RAID. This cutting-edge method of communication could be used regardless of time and place and ignored all interference by distance, weather, or terrain.

<a id="p0176"></a>**[p0176]** Synchronization complete. No issues during connection. Static rustled in her ears, different from the sounds of the room she was in.

<a id="p0177"></a>**[p0177]** “Handler One to all units in the Spearhead squadron. It’s a pleasure to meet you all. I will be serving as your commanding officer starting today.”

<a id="p0178"></a>**[p0178]** There was a long, somewhat hesitant pause. Lena found that disheartening. No one in the squadron knew how to respond to an officer greeting them for the first time like this, even though that should be proper etiquette among fellow humans.

<a id="p0179"></a>**[p0179]** But the hesitation disappeared from the line after a moment, and a quiet, young-sounding voice responded from the other side of her Resonated senses.

<a id="p0180"></a>**[p0180]** “Pleased to meet you, Handler One. This is the Spearhead squadron’s captain, Personal Name: Undertaker, speaking.”

<a id="p0181"></a>**[p0181]** Contrary to his ominous name, his pronunciation and enunciation were accurate and clear, and his voice was as serene as a deep forest lake. It was a boy roughly her age, probably originally from a middle-class or higher family.

<a id="p0182"></a>**[p0182]** “I’ve been informed of the change in Handlers. I wish you luck in your endeavors going forward.”

<a id="p0183"></a>**[p0183]** Lena smiled, able to vividly imagine his silent disposition from his detached tone. Yes, she could tell easily by simply conversing with him like this, and there was no way he could deceive her.

<a id="p0184"></a>**[p0184]** They were human beings. They were not something subhuman, something known only as an Eighty-Six.

<a id="p0185"></a>**[p0185]** “I wish the same to you. I look forward to working with you, Undertaker.”
