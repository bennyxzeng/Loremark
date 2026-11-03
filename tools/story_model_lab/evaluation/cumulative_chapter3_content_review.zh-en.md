# 《86》第一卷前三章 Story Model 对照评审 / Chapters 1–3 Story Model Review

## 中文

### 1. 总体判断与评审范围

**这版已经是很有用的角色与情节索引，尤其第三章的身份揭示和主要冲突抓得不错；但还不能直接作为可靠的“读到这里，故事目前是什么状态”的知识库。** 最大的问题不是没有记住人物名字，而是有时记错“谁在想这件事”，把人物说法升级为事实，把过去成立的状态留成没有时间边界的属性，以及压缩掉使行为成立的原因。

如果目标是帮助读者回忆“谁是谁、发生过什么”，目前基础不错。如果目标是解释“为什么赛欧会骂蕾娜、辛为什么被队员依赖、第三章结束时双方究竟是什么关系”，还需要补强。对只看过动画的读者，后者恰好是这几章小说最值得细读的部分。

本次直接阅读本地英文 EPUB 对应的前三章及其规范化输入，再对照最新 JSON。这里的“原文”指项目中的**英文小说文本**，不是日文原版；中文人名为便于阅读的译写，定位以英文名、记录 ID 和段落 ID 为准。不使用第四章以后、其他卷或动画中的知识补答案，也不据动画判断小说的对错。以下包含小说前三章完整剧透。

| 项目 | 本次对象 |
| --- | --- |
| 评审日期、评审者 | 2026-11-02；Codex，AI 评审，非人工终审 |
| 模型 | [stores/86v1/story_model.json](../stores/86v1/story_model.json) |
| 修订 | revision 3，`5102de8a4915` |
| 原书 | [86v1_chapters.epub](../../../sample_epub/86v1_chapters.epub) |
| 范围 | Chapter 1 / `section-004`：185 段；Chapter 2 / `section-005`：285 段；Chapter 3 / `section-006`：365 段 |
| 未覆盖范围 | `section-001`～`section-003`，以及第三章之后；不能称为“全书从开头至今的完整知识” |
| 实体 | 49 个存储实体：28 个 character、12 个 location、9 个 organization；其中父亲的两个实体已有明确身份链接 |
| 记录 | 337 条，当前有效 326 条；56 名称、34 别名、139 属性、35 关系、62 事件、9 疑点、2 身份链接 |
| 转换 | 11 条：9 次 supersede、2 次 resolve；7 个疑点仍有效 |

三个输入文件的哈希与模型登记一致，EPUB 哈希也一致。将空白规范化后，三个章节的正文段落均可在对应 XHTML 中定位；章标题是抽取器组合的标题文本。检查全部记录和转换的 **400 个 evidence 项，400 个引文均在所标段落逐字存在**。这证明引用定位正确，**不证明引用足以支持主张**。前三章输入共省略 13 张图片，本评审不评价插图信息。

本次先根据正文列出 23 个信息点，再逐类查看模型；没有沿用旧评审中的记录 ID。另以每章新增的属性、关系、事件分别取首条、中间条、末条，做 27 条固定选位复核，并追加问题导向检查。完整性清单、选位复核见后文；不把它们换算成全模型准确率或全章召回率。

### 2. 小说前三章实际在做什么，以及模型保留了多少

#### 第一章：所谓“零伤亡”，首先是一套命名和制度

开篇不是单纯介绍“有一群被歧视的少年在战斗”。小说先让读者看到首都的街道、家庭、旗帜和新闻，再逐渐拆开它们的意义：国家高举自由、平等、博爱等价值，街上却只剩白系种；新闻每天宣称无人伤亡，因为真正战斗的人已经被排除在人类和公民的统计之外。Juggernaut 明明有人驾驶，驾驶者却被命名为信息处理单元，机器便可以继续叫“无人机”。这不是所有人都不知道真相，而是制度用词语使人不必面对真相。（C1:p0002–p0015、p0035–p0050）

模型记录了新闻、迫害法令、集中营、劳动与驾驶员身份，`f000125`、`f000132–f000134` 提供了主干。但几个记录之间缺少明确的解释联系：**剥夺人的身份 → 把驾驶员记成零件 → 死亡不计为伤亡 → 墙内的人得以继续认为自己文明而人道。** 读者可以自己拼出来，下游问答却未必稳定地拼得出来。

这一章已经安排了一次第三章冲突的预演。蕾娜原来的部队损失七人，她道歉、致意，Pleiades 的驾驶员回以冷淡和蔑视。这说明后来赛欧的爆发并非突发的“队员不领情”：**安全地旁观、表达哀悼，与承担损失之间的距离，从第一章就存在。** `f000135–f000136` 记住了事件，但没有保留这种跨章呼应。（C1:p0051–p0064；C3:p0161–p0177）

蕾娜身边的三类成年人也值得分开理解。母亲公开把八六当牲畜；卡尔修塔尔在私人关系上关心蕾娜，却要求她不要上报不存在于官方统计中的伤亡；安妮特认真工作，也真心担心好友，却能轻描淡写地说不在乎八六的死活。这比“善良女主对抗一群坏人”更复杂：**亲切、勤勉、关心亲友，都可以和制度性的残酷共存。** 模型有这些台词和事件，却更偏重军衔、外貌、职位，较少把这种稳定的行为矛盾组织起来。（C1:p0072–p0088、p0116–p0124、p0136–p0162）

本章还提供两条必须保留来源限制的知识线：共和国依据缴获机器推算军团两年后停机；Para-RAID 的公开安全说法与安妮特透露的知识缺口并不一致。前者包含预测和推理前提，后者包含技术风险及被迫害研究者的失踪。不能把它们都当成读者已经获得的无条件世界设定。（C1:p0146–p0159）

#### 第二章：日常生活与战斗能力，是同一件事的两面

第二章开头那块久条（Kujo）的退役倒计时黑板非常重要：数字停了，因为每天修改它的人已经死了。随后是维修抱怨、篮球、做饭、洗衣、玩笑和搜集物资。小说不是忘记了战争；它先让人看见，所谓“八六”是会嫌饭难吃、互相逗弄、珍惜闲暇的具体少年。`f000236–f000242` 大体保留了这些生活场景。（C2:p0002–p0111）

但这些闲暇有一个关键前提：**辛使他们能够预先知道敌袭，不必像其他部队一样时时警戒。** 他不只是击杀数高的王牌，还给队友创造了休息和像人一样生活的余地。原文先通过阿尔德雷希特的评价和队员不用巡逻的反常生活展示结果，再通过预警、敌军阵形感知让读者看见能力。模型写了“生活相对轻松”和预警事件，却没有清楚记录“不看屏幕也能感知敌军”的能力及其对生活的作用。（C2:p0027–p0028、p0118–p0124、p0136；`f000238`、`f000243`）

这时不应从后文补出能力原理。模型应当敢于记录**已经发生的异常现象**，同时保留**尚未解释的机制**。现在的结果在这一点上太保守：保留了谜语，漏掉了一部分可直接观察的能力。

莱登和 Fido 在樱花树下发现共和国士兵遗骨的段落，也不是可有可无的散步。莱登知道死者可能是白系种，仍把对方当作战死的士兵，认为树下已经是一座很好的坟墓。与共和国不许八六收殓和立墓形成对照：**被剥夺尊严的人仍在主动决定如何尊重别人。** `f000242` 记住了致意，但 Fido 在第二章还没有实体，历史、与辛的关系和收集遗物的职责没有结构化保存。（C2:p0103–p0111）

战斗中的蕾娜也不是完全无能。莱登认可她选择阵地的判断；她找到可能的远程观测单位，帮助处理炮击。但辛又提醒她，用定向激光传数据可能暴露位置，战斗中应口头传达。小说同时写出了她的专业能力与实战盲点。模型保留了帮助定位的一面，漏掉危险的传输方式和随后的纠正，容易让“成长”只剩结果。（C2:p0155、p0183–p0189；`f000247`）

辛近距离击破重型军团的场面，原文还明确强调代价：机体承受不了这种动作，战后可能濒临报废，他也随时会被护卫敌机围杀。与开头维修队的怒骂连起来看，那不是单纯搞笑，而是对孩子能否活着回来的焦虑。`f000237` 和 `f000248` 分别有维修和战斗，因果联系较弱。（C2:p0014–p0031、p0201–p0217）

最后，辛一边读书一边说自己不太会读写，是逃避报告的借口；队友立即拆穿。模型没有把“辛不识字”存成事实，这是优点。蕾娜接着谈退役后的生活，队员看向辛，他只给出淡淡的回应；**气氛已经提示她的期待与他们的经验不在同一个层面**，但到本章为止不应替小说说明全部原因。（C2:p0254–p0285）

#### 第三章：善意开始接受对方的检验

第三章前半的猫、聊天和流星雨，承担了很重要的铺垫。猫有很多临时称呼，却没有固定名字；稍后蕾娜才发现，自己关心猫叫什么，却一直没有问过队员的名字。**把两段并读，是文本结构所支持的解读，不是正文直接宣布的寓意。** 模型记录了猫和后来问名的事件，却没有表达这种呼应。（C3:p0017–p0039、p0175–p0178；`f000318`、`f000323`）

可蕾娜离开房间也不能仅仅解释为吃醋。小说直接进入她的记忆：父母被白系种士兵当靶子虐杀，姐姐随后被送上战场。她厌恶蕾娜的声音，也厌恶本属于家人般同伴的夜晚被侵入。与此同时，戴亚提醒她，辛并不是为了满足她的憎恨而“弄坏”管制官。模型保留了家庭惨剧和仇恨，但漏掉这句对辛意愿的重要限定。（C3:p0039–p0055；`f000306–f000307`、`f000319`）

凯耶（Kaie）接下来给出了另一种立场：她反感迫害，却不认为所有白系种都是坏人，也不认为所有八六都是好人。集中营内部同样会迫害少数血统的人，她自己就有相关经历。这不是替共和国开脱，而是拒绝用集体标签替代对个人的判断。模型在 `f000320` 中留下“不全是坏人”，却压缩掉了八六内部的歧视，以及她为什么有资格这样说。（C3:p0070–p0078）

蕾娜讲述救命恩人的爱国言辞，希望回应他们的高尚。凯耶则提醒：他们不是为了她想象的那种崇高理由而战。这个错位随后被赛欧明确挑破——**被迫战斗的人，不一定愿意被安全的人赋予一个漂亮的牺牲意义。** 这也是为什么凯耶说蕾娜“不是坏人”，小说却马上补充，她没有说蕾娜“是好人”。`f000320` 只保留了劝退，缺少这段冲突的思想内容。（C3:p0081–p0096、p0173）

凯耶之死的因果链相当具体。蕾娜找到了更好的地图，并成功建议可蕾娜调整狙击位置；地图却还没有送到前线。凯耶把表面像草地的地方当成可行驶地面，陷入沼泽，蕾娜和辛的警告都来不及阻止死亡。随后敌人利用遗体布置伏击，辛阻止安琪回收，安琪至少向机体残骸及周边开了一炮。不能简化成“蕾娜下错命令害死凯耶”，也不能只剩“凯耶被敌人杀死”。小说把装备缺陷、信息隔离、地形与战场残酷都放进了这一死因。（C3:p0102–p0153；`f000321–f000322`）

赛欧爆发时，责备的重点也不只是“没有问名字”。他首先指出双方处境不平等，蕾娜的礼貌并没有改变谁被迫战斗、谁安全吃饭睡觉的事实；最后才用姓名证明她并未真正认识他们。之后他又为自己的表达方式感到羞愧，觉得辜负了凯耶。**他的自责并不等于撤回批评，蕾娜受伤也不等于她的善意全是假。** 模型把责问和后悔分成 `f000323–f000324`，处理得不错，但对批评的结构和自责的价值依据记录不足。（C3:p0161–p0200）

辛与蕾娜的夜谈把“姓名”推进了一层。国家靠代号和不公开档案减少管制官承受死亡的负担；辛却把死者的名字刻在碎片上，随身带走。561 人首先是他记住的阵亡同伴数，并不能据此推导出此刻恰好有 561 块可清点的金属片——原文还说早期会用木片或其他材料。**国家抹掉的，辛在保存。** `f000299–f000300` 和 `f000327` 是本版很好的提取；如果再记录代号制度的作用，这组信息会更完整。（C3:p0219–p0247）

蕾娜还重新理解了辛的平静：他起初不动声色，不一定是温柔地包容她，也可能根本没有对她投入感情；而他对死去同伴的责任又确实深重。**一个人可以对同伴极其温柔，同时对一个远方的管制官十分冷淡。** 原文 p0211 与 p0243–p0250 的落差，是人物关系推进的重要部分；模型较少保留这种“对谁如此”的区别。

父亲带十岁的蕾娜看战场的回忆也不是纯粹的英雄故事。他反对迫害、想让女儿看见现实，却擅用飞机、忽视禁飞警告，并低估战场风险。叙述甚至指出，他可能也不自觉地觉得只有八六会死在那里。救她的雷（Rei / Shourei）则把尊严、不得不战斗的生存需要、想回到弟弟身边的个人愿望放在一起。模型保留坠机、救援、身份与返乡愿望，漏掉父亲理想与盲点并存的部分。（C3:p0261–p0275、p0297–p0307；`f000329–f000331`）

结尾的问名与继续联络，只是一次有限的关系修复。赛欧讲旧队长的故事，莱登也道歉，但二人明确说不把蕾娜当作平等的同伴。她仍决定继续联系，并承诺把地图送过去。`f000332` **没有把这一幕误写成全队已经接纳蕾娜**，这是很值得肯定的克制。至于辛为何寻找已经死去的哥哥、为什么不是寻找遗体、最后为什么碰围巾，本章仍保留悬念，模型也应保留。（C3:p0315–p0365）

### 3. 这版最值得保留的优点

| 优点 | 具体依据及价值 |
| --- | --- |
| 身份随阅读进展揭示 | Undertaker → Shinei Nouzen；Raiden、Theo 等到第三章补全姓名，旧称保留为别名。`t000001`、`t000004–t000008` 有清楚依据。 |
| 不把早期推断冒充早已知道的事实 | 父亲与 Václav 的身份从 `f000156` inferred 升为 `f000337` explicit，保留了“何时能够确认”。 |
| 疑点可以得到局部解答 | 蕾娜的救命恩人、辛在找谁得到解答；“哥哥已死，为何仍找他”则新增为 `f000335`。解答一个问题没有被当成解答所有问题。 |
| 第三章重大事件没有丢 | 凯耶战死、赛欧责问、夜谈、纪念死者、雷的救援及兄弟身份、第二天重新问名都在。 |
| 主要回忆识别正确 | 父亲带蕾娜上飞机、雷救人标为 past；九年前战争也未写成当前才发生。过去标签与叙述顺序仍需分别检查，见下节。 |
| 结尾关系没有过度美化 | `f000332` 保留继续交谈与拒绝视为平等同伴并存的状态。 |
| 审核条件较好 | 原文段落、稳定 ID、历史转换齐全。错误能精确指出位置，而不只是说“感觉摘要不太对”。 |

这里还需要区分**读者知道**与**人物知道**。读者在第二章已经知道辛的真名，蕾娜却到第三章才主动问名。因此第二章更新 `c006` 的主名称是正确的；不应为了迁就蕾娜视角把读者已经知道的姓名隐藏。未来若要回答“蕾娜当时知道什么”，才需要另外记录人物的获知事件或知识范围。

### 4. 需要优先修正的不足

#### 4.1 明确的归属或行为错误

**老妇人的回忆被归错给辛。** `f000334` 问的是“辛从生产设施记起的老妇人是谁”，并关联 `c006`。C3:p0010 明确切到莱登，p0014–p0016 是他喝咖啡、想起那位老妇人的思绪；辛此时在读书。应关联 `c018`，问题只问“莱登想起的老妇人是谁、她与他是什么关系”。“来自生产设施”也不是已建立的身份信息。她是谁依然未知，**谁在回忆她则已经明确**。

**卡尔修塔尔被加上了并未说过的话。** `f000146` 写他表示帝国灭亡使拘禁失去理由、民众拒绝改变；C1:p0122 是叙述说明，p0123 是蕾娜发言，卡尔修塔尔实际在 p0124 劝她收敛理想。把叙述归给他，会改变这个人物在争论中的立场。

**“要求结束通话”被改成“亲自结束通话”。** `f000323` 写 Raiden closes the Resonance；C3:p0186 是他要求蕾娜关闭，p0190 明确是她执行。应保留“莱登要求、蕾娜关闭”的行动顺序。这是小错误，但很能说明引文包含动词不等于模型正确识别了动作主体。

#### 4.2 事实来源标签没有贯彻

238 条带 assertion 的记录中，231 条为 explicit，只有 2 条 reported、5 条 inferred。这个比例本身不证明错误，但与本书大量广播、传闻、自述和受限视角形成鲜明对照。

| 记录 | 问题 | 更妥当的处理 |
| --- | --- | --- |
| `f000093–f000094` | 把新闻中的入侵、撤防和遣散说法直接写成 explicit 属性。 | 保存为共和国广播的 reported 主张；“发生了这次播报”的事件仍可是 explicit。 |
| `f000053` | 安妮特自称 certified genius，被变成客观的技能属性。 | 保留为她的自我描述，或删除“认证”性质的事实断言；不能凭这句玩笑证明存在认证。 |
| `f000280–f000281` | 雷已死及死亡时间仅引辛的话，却标 explicit。 | 按本项目口径标 reported，来源 `c006`。这不表示辛说谎，而是准确记录知识来源。 |
| `f000101` | 检查缴获机器的发现与“全部军团两年后停机”的预测混成一条属性。 | 拆分检查结果、共和国的预测及其前提；预测可用 reported + future 事件。现有 value 写了 expected，已有一定克制，但来源仍不充分。 |

不要机械地把所有对话事件改成 reported。例如 `f000328` 写“辛说哥哥已经死了”，记录的是实际发生的谈话，可以是 explicit；从谈话提取出“哥哥客观已经死了”则是另一条主张。`f000125` 写“新闻报道零伤亡”也不等于模型断言真的零伤亡。

#### 4.3 累计记录缺少有效时间边界

`current.active_record_ids` 的意思是“尚未被撤回或替代”，不等于“此刻仍成立”。因此不能看到历史事实还 active 就一律判错。真正的问题是，有些记录本身没有保留足够的时间限定，下游展示很容易混淆。

- `f000115` 仍是 Lena → Pleiades 的 `commands/current`，但第一章末她已调任；`f000048` 又正确称其为 former_role。关系视图与属性视图不一致，应把旧指挥关系表达为历史任职。
- `f000196` 的“任职一周”到第三章“半个月”时仍有效。它是第二章正确的相对时间，不应变成第三章人物卡上的无日期描述。
- `f000312` 的“半个月零伤亡”在第三章开头成立，凯耶死后仍 active。应限定为“第三章开头、凯耶死亡前的半个月”；不要删除历史事实，也不要作为无时间范围的当前战绩。
- `f000223` 的 21 架出动是第二章那场战斗的数据，不应直接当第三章末编制人数，更不应自行算出此后人数。
- `f000113` 把九年前“帝国宣战”的依据用在 `at_war_with/current` 上，而模型同时记有帝国已经覆灭。应至少区分历史上的帝国宣战与当前仍在同军团作战。

这里不只是 prompt 不够严格。当前属性没有独立时间字段，且转换不能指向同一次增量新建的记录；关系 supersede 又要求 temporal_context 相同。因此“本章开头正确、章中失效”及“current 改为 past”不能随便用现有 supersede 硬做。短期可把时点写清、把一次性状态放进事件；长期再设计有效区间或状态结束机制。

#### 4.4 叙述顺序与事件粒度

`f000325` 的旧队长临终无线电回忆引用 C3:p0339–p0344，却排在 narrative_order 9，早于 p0201 开始的夜谈 `f000326`。小说直到第二天的交谈才完整讲出这段往事。不能因为 p0196 提到“旧队长”，就把后面的临终细节整个前移；那会破坏读者获得信息的顺序。

`f000328` 更明显地跨越了倒叙：它把 p0258 的“你认识雷吗”与 p0311–p0321 的兄弟确认、死亡和寻找合成一个事件，然后才列飞机和救援的回忆 `f000329–f000331`。应拆为**问起姓名 → 童年回忆 → 回到现在确认兄弟身份并谈寻找**。这些事件都在同一章内，但阅读体验和揭示顺序仍然重要。

第二章 `f000250–f000251` 先列射击比赛、再列晚饭，倒是符合小说的讲述顺序：先写饭后比赛，再补述吃了什么。不能一概按世界时间把它们重排。问题在于单一事件又把此前晚饭与后来送咖啡、阅读谈话混在一起，难以表达不同时间层。

#### 4.5 引文匹配与语义支持有明显差距

`f000248` 声称 Fido 补给后辛近战击毁多台 Löwe，唯一引文却只有 “Undertaker fired.”；`f000240` 包含晴人带来野猪、赛欧煮果酱及晚餐安排，引用却只说人在厨房。整段或相邻段落往往确实支持这些内容，**所以不必把它们一律称作编造；但证据链并没有支持完整主张**。

类似地，`f000247` 把蕾娜的候选观测点写成观测单位坐标，遗漏 p0183 的“可能目标、请确认”。应保留“候选”限定，再分别记录辛确认/下令。优先让每条事件只承载一个主要动作，并为关键数量、原因、参与者和结果各提供足够证据，比单纯增加引文长度更有效。

#### 4.6 关系结构比事件文字薄，补入实体也有滞后

第三章新增 82 条记录，其中只有 4 条关系。关系少本身不代表差，但这里确实漏了有价值的关系：

- 凯耶、可蕾娜、安琪没有相应的 Spearhead `member_of` 关系，虽然其他一些队员有。读全文能知道她们是谁，单查关系图却可能漏人。
- C2:p0275 的安琪与戴亚自入伍起同队、凯耶与晴人同年入伍、赛欧和可蕾娜与辛及莱登的两年经历没有完整建模。
- Fido 在第二章已反复被叫名字、补给、收集遗物、协助射击游戏，却到第三章才创建 `c027`，只有 Scavenger 属性。第二章的名称、历史和行动没有因此自动补回。

Fido 是否算 character 可以有分类取舍，但同一套规则应前后一致。当前 prompt 又限制新增证据只能来自新章，因此第三章不能合法地凭记忆补第二章引文；应在独立复核/重建流程中处理，不能悄悄倒改历史。

此外，`participant_ids` 混入了仅被提及的人。`f000236` 的当前场景是辛看倒计时，却列十天前已死的久条为参与者；`f000333` 是辛想哥哥，却把哥哥也列为当前参与者。若消费端用于共现或场景人物，容易产生假关系。应区分实际行动者与被谈论、被回忆的对象。远程通话的单一 location_id 也应避免被解释为所有参与者共处一地。

### 5. 预先选定的 23 个信息点：覆盖情况

下面是阅读正文后、逐类查看模型前登记的复合信息点。`完整` 表示核心子项有明确、基本可靠的记录；`部分` 表示有主干，但缺少关键限定、子项或因果。该清单不是全部重要信息，也不是等权计分量表。后续发现的关系图缺边、老妇人归属等另在上节报告，没有反过来重写此清单。

| 信息点 | 原文 | 覆盖 | 模型依据与缺口 |
| --- | --- | --- | --- |
| C1-01 零伤亡与制度性非人化 | p0038–p0050 | 部分 | `f000132–f000134` 有法令与驾驶员；命名如何消除伤亡统计未明确组织。 |
| C1-02 七人死亡及道歉受冷遇 | p0051–p0064 | 完整 | `f000135–f000136`。 |
| C1-03 反对母亲、救援记忆与动机 | p0076–p0088 | 部分 | `f000138–f000140` 有事件，动机联系较弱。 |
| C1-04 任命与死神传闻 | p0099–p0125 | 完整 | `f000141–f000147`、`f000070`；其中 `f000146` 另有说话人错误，不作为此项依据。 |
| C1-05 停机预测与 Para-RAID 安全疑点 | p0146–p0159 | 部分 | `f000101`、`f000149`；预测来源、理论缺口及风险限定不足。 |
| C1-06 首次接触与蕾娜的判断 | p0177–p0185 | 完整 | `f000151–f000152`。 |
| C2-01 倒计时停止、久条死亡、禁止立墓 | p0002–p0028 | 部分 | `f000201–f000202`、`f000236`；禁墓在第三章才经 `f000327` 间接补到。 |
| C2-02 辛的预警使日常生活成为可能、假报告 | p0027–p0044 | 部分 | `f000238–f000239`；缺能力与生活的因果。 |
| C2-03 Fido 历史与莱登尊重遗骨 | p0103–p0111 | 部分 | `f000242`；Fido 历史缺失。 |
| C2-04 异常预警、Sheep / Shepherd 悬念 | p0115–p0131 | 部分 | `f000243`；术语疑点到第三章 `f000336` 才建立。 |
| C2-05 蕾娜的战术贡献与激光传输风险 | p0155–p0189 | 部分 | `f000247`；漏风险及纠正，候选目标限定不足。 |
| C2-06 辛的战技及机体、人身代价 | p0201–p0217 | 部分 | `f000193`、`f000248`；代价和维修场景的联系弱。 |
| C2-07 阅读压低声音、假称不识字、退役话题不适 | p0234–p0285 | 部分 | `f000251–f000252`；谎言被识破与气氛未明确保留。 |
| C3-01 猫无固定名、可蕾娜创伤、老鼠借口 | p0017–p0055 | 部分 | `f000318–f000319`、`f000306`；没有保留辛用老鼠掩饰。 |
| C3-02 凯耶反对群体标签与高尚动机投射 | p0070–p0096 | 部分 | `f000320`；八六内部歧视及被强加的战斗意义被压缩。 |
| C3-03 地图、炮击支援及制度阻碍 | p0102–p0129 | 部分 | `f000321` 有阵地调整；缺申请炮击被拒和地图流通问题。 |
| C3-04 沼泽死亡、回收受阻、安琪炮击 | p0135–p0157 | 部分 | `f000322`；缺安琪随后开炮。 |
| C3-05 赛欧批评不平等与姓名、又后悔过激 | p0161–p0200 | 部分 | `f000323–f000324`；批评与自责的理由较薄，关闭通话主体错误。 |
| C3-06 问名、制度、561 人纪念与冷淡/温柔 | p0211–p0255 | 部分 | `f000299–f000300`、`f000327`；缺制度功能和对象不同的情感区别。 |
| C3-07 父亲的理想和冒险、雷的救援与求生愿望 | p0260–p0307 | 部分 | `f000329–f000331`；父亲风险判断和盲点缺失。 |
| C3-08 哥哥身份、据称死亡、寻找的不是遗体 | p0308–p0324 | 部分 | `f000328`、`f000335`；未保留明确否认“找遗体”，死亡来源标签需改。 |
| C3-09 逐人问名、旧队长、有限的继续交谈 | p0325–p0362 | 完整 | `f000332`、`f000325` 有内容；后者叙述排序另需修正。 |
| C3-10 姓名与围巾留下悬念 | p0363–p0365 | 完整 | `f000333` 有内容；参与者字段另需修正。 |

这里的“完整”只评价信息点内容是否被保留，不等于所涉记录每个字段全部正确。尤其最后两项同时展示了：**情节覆盖可以不错，结构化字段仍然会错。**

### 6. 固定选位复核：27 条记录

选位规则为每章、每类首条 / 靠前的中间条 / 末条；中间位置按 `floor((n-1)/2)` 取零基下标。表中按整条记录和段落上下文判断，并另指出短引文不足。该规则是在通读模型后执行，非盲评；作用是避免报告只列自己挑出的坏例子。样本覆盖各章前、中、后段，另以第 4 节追加检查捕获未入样问题。

| 章 / 类别 | 记录与原文 | 判断 |
| --- | --- | --- |
| C1 属性 | `f000040` p0008；`f000072` p0181；`f000104` p0049 | 均 supported；年龄近似仍保留“roughly”，旧年龄随后被替代。 |
| C1 关系 | `f000105` p0008；`f000114` p0003；`f000124` p0004 | 均 supported，结合全章确认军籍、战争及首都关系；`f000114` 可补更独立于广播的证据。 |
| C1 事件 | `f000125` p0003；`f000138` p0072–p0077；`f000152` p0180–p0184 | 均 supported（全文语义）；前两条短引文只覆盖部分摘要。`f000125` 记录播报行为，不认定播报为真。 |
| C2 属性 | `f000184` p0013；`f000204` p0046；`f000224` p0157–p0181 | 均 supported；军团机型有多条对应引文。 |
| C2 关系 | `f000225` p0003–p0004；`f000230` p0075；`f000235` p0146 | 均 supported；久条所属标 past，远程指挥关系与前文一致。 |
| C2 事件 | `f000236` p0003–p0004；`f000244` p0130–p0134；`f000252` p0235–p0285 | `f000236` unsupported：死者列为当前参与者；后两条 supported（全文语义），但引文未覆盖简报/伏击和全部报告要求/退役话题。 |
| C3 属性 | `f000280` p0315；`f000296` p0145–p0146；`f000312` p0004 | `f000280` unsupported：reported 内容标 explicit；`f000296` supported，宜补完整死亡描述引文；`f000312` needs_review：章初事实正确，作为章末无时点属性有歧义。 |
| C3 关系 | `f000313` p0311–p0313；`f000314` p0285–p0288；`f000316` p0103 | 均 supported；兄弟关系有叙述确认，救援方向正确，运输部门隶属标 inferred 合理。 |
| C3 事件 | `f000317` p0002–p0004；`f000325` p0339–p0345；`f000333` p0364–p0365 | `f000317` supported，补 p0003 可覆盖联络；`f000325` unsupported：叙述顺序前移；`f000333` unsupported：哥哥仅被回忆，不是当前行动者。 |

`unsupported` 在这里也包括标签、顺序或参与者不支持，不能读成“该段情节全是编造”。`needs_review` 是明确标示的解释/展示边界问题，不应与确定错误混为一谈。

### 7. 建议下一轮怎样改

1. **先修确定错误。** 老妇人的回忆归莱登；去掉卡尔修塔尔未说过的话；恢复谁要求、谁关闭通话；修第三章倒叙与旧队长故事的顺序。使用可审计的修正或重跑流程，不直接篡改已提交历史快照。
2. **给每个主张检查来源。** 分开“某人说了 X”和“X 为真”；预测保留预测者与前提；内心独白先确认当前视角人物。优先检查广播、死亡自述和对人物动机的概括。
3. **让关键事件更小、证据更完整。** 一条主要动作配足够证据，避免把整场夜谈、多个时间层或好几个独立揭示合成一条。检查的不只是 description，还有 participant_ids、location_id 和 narrative_order。
4. **补机制、能力、动机和关系，而非先补更多外貌。** 优先补辛的预警与休息、地图和炮击支援受阻、Fido 与辛、凯耶对群体标签的拒绝、姓名制度与纪念行为的联系。文学解释可以作为带证据的阅读笔记，不能伪装成 explicit 事实。
5. **区分历史知识与当前状态。** 短期给相对时间和统计写明锚点，长期考虑属性有效区间、关系结束、人物获知事件，以及实际参与者与被提及对象的区别。无需为本次所有问题立刻大改 schema。
6. **用同一批来源定位做下一版对照。** 复核本报告具体问题及 23 个信息点；记录补全是否带来新的过度推断。不要把“条数更多”自动等同于“理解更好”。

我会优先保住现在的身份历史和悬念处理，再改善因果与来源。对这三章而言，真正值得多保存的不是又一条发色，而是：**共和国如何抹去名字，辛如何留下名字，蕾娜又如何终于开始向本人问名字。**

### 8. 运行与复核标识

三个提交均登记 provider `deepseek`、model / response_model `deepseek-flash`。运行依次为 `86v1-ch1`、`86v1-ch2`、`20261102T002241Z-b272de`。前两章有 3 处已登记人工引用修正：一处引号、两处段落定位；第三章提交登记无人工修正。本评审只新增文档，没有修改模型。

```text
model file SHA-256:
ca9e742104c5ddc8d84f4c4a4800e4fe21db930a80ae275ef368de96fefc2190
EPUB SHA-256:
452d8183147c1d20a0d474b8d0c981556b2f1bdb4bfb7151c25729f413911317
prompt SHA-256 (all three committed runs):
ed09bd6c6cb3dd138763583d18688c826d0b83c285fdbdc4ef6a3470ea1a1c76
schema SHA-256 (all three committed runs):
70e8068ec2ca9cfdce0a1e3df5cdc391a4d132ce966fdda5a2459a578a3f42fd
```

原文定位索引：C1 = [section-004 input](../stores/86v1/inputs/section-004-d1053fa1bbdd5a16.json)；C2 = [section-005 input](../stores/86v1/inputs/section-005-1f5791967938e77a.json)；C3 = [section-006 input](../stores/86v1/inputs/section-006-c088eb42012207fd.json)。这些输入是本地配套文件，未必随仓库分发。格式判断参照 [格式说明](../STORY_MODEL_FORMAT.zh-CN.md) 和 [update prompt](../src/loremark_story_lab/prompts/update_story_v2.txt)。

---

## English

### 1. Overall assessment and scope

**This version is already a useful character and plot index, particularly for Chapter 3’s identity revelations and central conflict. It is not yet a dependable knowledge base for “what is true at this point in the story.”** Its main weaknesses are not failures to remember names. They are occasional mistakes about whose thoughts we are reading, the promotion of testimony into fact, attributes without adequate time boundaries, and the loss of reasons that make actions meaningful.

For recalling who people are and what happened, the foundation is good. For explaining why Theo confronts Lena, why the squad depends on Shin, or precisely what relationship exists at the end of Chapter 3, it needs more work. Those are also some of the most rewarding aspects of these chapters for someone who has watched the anime but has not closely read the novel.

I read the three chapters in the local English novel text and its normalized inputs, then compared them with the latest JSON. “Source text” here means the project’s **English novel text**, not the Japanese original. This review does not use later chapters, other volumes, or the adaptation to fill gaps or judge correctness. It contains full spoilers through Chapter 3.

| Item | Reviewed material |
| --- | --- |
| Date and reviewer | 2026-11-02; Codex, an AI review rather than final human verification |
| Model | [stores/86v1/story_model.json](../stores/86v1/story_model.json) |
| Revision | 3, `5102de8a4915` |
| Book | [86v1_chapters.epub](../../../sample_epub/86v1_chapters.epub) |
| Coverage | Chapter 1 / `section-004`: 185 paragraphs; Chapter 2 / `section-005`: 285; Chapter 3 / `section-006`: 365 |
| Exclusions | `section-001`–`section-003` and everything after Chapter 3; this is not complete knowledge from the very beginning of the book |
| Entities | 49 stored entities: 28 characters, 12 locations, 9 organizations; two representations of Lena’s father are explicitly linked |
| Records | 337 total, 326 active: 56 names, 34 aliases, 139 attributes, 35 relationships, 62 events, 9 uncertainties, 2 identity links |
| Transitions | 11: 9 supersedes and 2 resolutions; 7 uncertainties remain active |

All three input-file hashes match the model’s metadata, as does the EPUB hash. After whitespace normalization, the body paragraphs are locatable in the corresponding XHTML; chapter headings are assembled by the extractor. All **400 evidence items** across records and transitions contain quotations found verbatim in their designated paragraphs. This verifies quotation location, **not whether each quotation supports its entire claim**. The inputs omit 13 images in total; this review does not assess illustration content.

I selected 23 information points from the source before inspecting the model category by category. I did not reuse record IDs from older reviews. I also checked 27 records by taking the first, middle, and last newly introduced attribute, relationship, and event in each chapter, with additional targeted checks. Neither exercise is presented as overall model accuracy or full-chapter recall.

### 2. What the novel is doing, and how much the model preserves

#### Chapter 1: “Zero casualties” is a system of naming and institutions

The opening does more than introduce persecuted young soldiers. It first presents the capital’s streets, families, flags, and news, then dismantles their apparent meaning. A country celebrating freedom and equality has streets populated only by Alba. The news reports no casualties because the actual combatants have been excluded from the categories of human beings and citizens. Juggernauts have pilots, but calling those pilots information-processing units allows the machines to remain officially “unmanned.” This is not simply universal ignorance: institutional language lets people avoid confronting what they know. (C1:p0002–p0015, p0035–p0050)

The model captures broadcasts, the discriminatory decree, internment, forced labor, and the pilots’ designation. `f000125` and `f000132–f000134` provide the framework. What remains weak is the connection: **remove human status → classify pilots as components → exclude their deaths from casualty counts → preserve the population’s belief in its own humanity.** A reader can reconstruct this; downstream answers may not do so consistently.

The chapter also rehearses the conflict that will erupt in Chapter 3. Seven members of Lena’s former squadron die. She apologizes and pays tribute; Pleiades’s Processor responds with cold contempt. Theo’s later outburst is therefore not an isolated instance of soldiers rejecting kindness. **The distance between offering condolences from safety and bearing the loss is present from the beginning.** `f000135–f000136` preserve the incident but not this cross-chapter connection. (C1:p0051–p0064; C3:p0161–p0177)

The adults around Lena occupy distinct positions. Her mother openly treats the Eighty-Six as livestock. Karlstahl cares for Lena personally but tells her to stop recording casualties excluded from official statistics. Annette works seriously and worries sincerely about her friend while dismissing the lives of the Eighty-Six. The novel is more complicated than a good heroine confronting uniformly bad people: **affection, diligence, and concern for friends can coexist with institutional cruelty.** The model retains relevant dialogue and events, but organizes rank, appearance, and occupation more consistently than these contradictions. (C1:p0072–p0088, p0116–p0124, p0136–p0162)

Two knowledge threads particularly require source qualifications. The Republic predicts that the Legion will stop functioning in two years based on captured machines. Annette’s account of Para-RAID exposes gaps beneath its public assurance of safety. One involves a forecast and its assumptions; the other involves technical risk and the disappearance of a persecuted researcher. Neither should become an unconditional encyclopedia entry. (C1:p0146–p0159)

#### Chapter 2: Everyday life and combat ability are connected

Kujo’s service countdown is a powerful opening detail: the number has stopped changing because the person who updated it is dead. The chapter then moves through maintenance complaints, basketball, cooking, laundry, jokes, and scavenging. The war has not been forgotten. These scenes establish that the supposedly interchangeable Eighty-Six are particular teenagers who dislike bad food, tease each other, and treasure leisure. `f000236–f000242` preserve much of this activity. (C2:p0002–p0111)

Their leisure has an essential condition: **Shin gives them advance warning of attacks, so they do not have to remain constantly on guard like other squadrons.** He is not merely an ace with an exceptional kill count. He creates room for his comrades to rest and live human lives. The novel first shows the effect through Aldrecht’s comments and the absence of routine patrols, then shows the strange warning and perception of enemy formations. The model records a comparatively easy life and a warning event, but does not clearly preserve Shin’s ability to perceive enemies without looking at a screen or its effect on everyday life. (C2:p0027–p0028, p0118–p0124, p0136; `f000238`, `f000243`)

The mechanism should remain unexplained at this point. The model can record an **observed extraordinary phenomenon** while leaving its **cause unresolved**. Here it is too conservative: it preserves mysteries while omitting some directly observable capabilities.

Raiden and Fido finding a Republic soldier’s remains under a cherry tree is similarly consequential. Raiden recognizes that the soldier may be Alba, yet treats him as a person who died in battle and regards the tree as a fitting grave. This contrasts with the Republic’s prohibition on recovering and burying Eighty-Six bodies: **people denied dignity still choose how to respect someone else.** `f000242` preserves the act of respect, but Fido has no entity in Chapter 2, and its history, relationship with Shin, and duty of collecting keepsakes are not retained structurally. (C2:p0103–p0111)

Lena is not simply incompetent in battle. Raiden recognizes the merit of her proposed interception position. She identifies possible observer targets to help counter artillery. Shin nevertheless has to warn her that laser data transmission may reveal their position and that she should communicate orally during combat. The source holds competence and inexperience together. The model preserves the useful targeting contribution while omitting the dangerous method and correction, weakening the account of her learning. (C2:p0155, p0183–p0189; `f000247`)

Shin’s close-range destruction of heavy Legion also has a stated cost. The Juggernaut cannot withstand such maneuvers indefinitely; it may be nearly wrecked afterward, and escort units could kill him. Read alongside the maintenance scene, Aldrecht’s anger is not just comedy. It expresses anxiety about getting the children home alive. `f000237` and `f000248` separately retain maintenance and combat but weakly connect them. (C2:p0014–p0031, p0201–p0217)

Finally, Shin’s claim that he cannot read or write well, made while reading, is an excuse to avoid reports. His comrades expose it immediately. The model does not store illiteracy as fact, which is good. Lena then asks about life after discharge. Everyone looks toward Shin, and he responds faintly. **The atmosphere signals a gap between her expectations and their experience**, but the model should not explain that gap with later revelations. (C2:p0254–p0285)

#### Chapter 3: Good intentions face the other person’s judgment

The kitten, conversations, and meteor shower prepare the chapter’s central confrontation. The kitten has multiple temporary names but no fixed one. Later Lena discovers that she asked about the cat’s name without ever asking the squad members for theirs. **Reading these scenes together is a text-supported structural interpretation, not an explicitly declared moral.** The model records both scenes but not their resonance. (C3:p0017–p0039, p0175–p0178; `f000318`, `f000323`)

Kurena’s departure cannot be reduced to romantic jealousy. The narration enters her memory: Alba soldiers tortured her parents as targets, and her sister was subsequently sent to the front. She hates Lena’s voice and the intrusion into evenings that belong to companions she regards as family. Daiya also reminds her that Shin does not break Handlers to satisfy her hatred. The model preserves the family atrocity and hostility, but omits this important limitation on Shin’s intention. (C3:p0039–p0055; `f000306–f000307`, `f000319`)

Kaie offers a different position. She resents persecution but refuses to classify every Alba as evil or every Eighty-Six as good. People with minority backgrounds also suffer within the internment camps, and she has experienced this herself. This does not excuse the Republic; it rejects collective labels as substitutes for judging individuals. `f000320` retains “not all Alba are bad” but compresses the persecution among the Eighty-Six and the experience behind her judgment. (C3:p0070–p0078)

Lena recounts her rescuer’s patriotic words and wants to honor their nobility. Kaie warns her that they are not fighting for the noble reason Lena imagines. Theo will later make the mismatch explicit: **people forced to fight may not welcome a beautiful meaning assigned to their sacrifice by someone safe.** That is also why Kaie calls Lena “not a bad person,” followed by the narrator’s observation that she has not called her a good person. The model preserves the warning to leave the job, but not enough of its substance. (C3:p0081–p0096, p0173)

Kaie’s death has a specific causal chain. Lena finds a better map and successfully proposes a new position for Kurena, but the map has not yet reached the front. Kaie enters what looks like grassland, becomes stuck in a marsh, and dies despite warnings from Lena and Shin. The enemy then uses her body as bait. Shin stops Anju from recovering her; Anju at least fires a shell into the wreck and surrounding area. This cannot accurately become either “Lena’s bad order killed Kaie” or simply “the enemy killed Kaie.” Equipment defects, withheld information, terrain, and battlefield cruelty all contribute. (C3:p0102–p0153; `f000321–f000322`)

Theo’s accusation is likewise not only about names. He first describes the unequal conditions: politeness has not changed who must fight and who can eat and sleep safely. The failure to ask their names then becomes concrete evidence that Lena has not truly known them. Afterward he regrets the cruelty of his expression and feels he has dishonored Kaie. **His regret does not retract his criticism, and Lena’s pain does not establish that all her kindness was false.** Separating the outburst and regret into `f000323–f000324` is good, though the reasons behind both are thin. (C3:p0161–p0200)

The nighttime conversation gives naming another dimension. Call signs and withheld personnel files reduce the burden of death on Handlers; Shin instead carves the names of the dead into fragments and carries them. The 561 are first and foremost fallen Processors he remembers, not necessarily exactly 561 countable pieces of metal: the text says that earlier memorials could use wood or other available material. **Shin preserves what the state erases.** `f000299–f000300` and `f000327` are strong extractions. Recording the institutional function of call signs would complete the contrast. (C3:p0219–p0247)

Lena also reinterprets Shin’s composure. His initial calm need not mean tender acceptance of her; it may mean that he has invested almost no feeling in her. His responsibility toward dead companions is nevertheless profound. **A person can care deeply for comrades while remaining indifferent to a distant Handler.** The difference between p0211 and p0243–p0250 matters to the development of their relationship; the model largely loses the distinction between whom his feelings concern.

The flashback involving Lena’s father is not an uncomplicated heroic memory either. He opposes persecution and wants his daughter to witness reality, but uses an aircraft without authorization, ignores a no-fly warning, and underestimates danger. The narration suggests he may himself have assumed that only Eighty-Six die on that battlefield. Rei, who rescues Lena, combines dignity, the necessity of fighting to survive, and a personal wish to return to his brother. The model captures the crash, rescue, identity, and desire to return, but not the father’s coexistence of ideals and blind spots. (C3:p0261–p0275, p0297–p0307; `f000329–f000331`)

The ending offers limited repair. Theo tells the story of his former captain, Raiden apologizes, and both still reject the idea that Lena is an equal comrade. She chooses continued contact and promises the map. **`f000332` does not turn this into full acceptance by the squad**, an important restraint. Why Shin searches for a brother he says is dead, why he denies searching for a body, and why he touches his scarf remain unresolved. The model should preserve that boundary. (C3:p0315–p0365)

### 3. Strengths worth preserving

| Strength | Evidence and value |
| --- | --- |
| Identities develop with reading | Undertaker becomes Shinei Nouzen; Raiden, Theo, and others receive full names in Chapter 3 while earlier forms remain aliases. `t000001` and `t000004–t000008` are well grounded. |
| Earlier inference is not retroactively treated as certainty | The father–Václav link moves from inferred `f000156` to explicit `f000337`, preserving when identification became secure. |
| Questions can be partially answered | Lena’s rescuer and the object of Shin’s search are identified; the paradox of searching for a dead brother becomes `f000335`. Answering one question does not answer everything. |
| Chapter 3’s central developments survive | Kaie’s death, Theo’s confrontation, the nighttime conversation, memorials, Rei’s rescue and identity, and renewed introductions are all present. |
| Major flashbacks receive past labels | The flight, rescue, and war’s beginning are not represented as newly occurring present events. Narrative placement still needs separate checking. |
| The ending is not sentimentalized | `f000332` preserves continued conversation alongside refusal to regard Lena as an equal. |
| The output is auditable | Paragraph references, stable IDs, and transitions allow specific corrections rather than impressionistic criticism. |

An important distinction is **reader knowledge versus character knowledge**. Readers learn Shin’s name in Chapter 2; Lena asks for it in Chapter 3. Updating `c006` in Chapter 2 is therefore correct. A reader-oriented model should not hide information merely because Lena does not yet know it. Answering what Lena knew at a particular moment would require separate knowledge-acquisition events or character-specific scope.

### 4. Weaknesses to prioritize

#### 4.1 Clear mistakes about attribution or action

**The old woman belongs to Raiden’s recollection, not Shin’s.** `f000334` asks about an old woman Shin remembers “from the production plants” and links `c006`. C3:p0010 switches to Raiden; p0014–p0016 follow his coffee and memories, while Shin is reading. The uncertainty should link `c018` and ask who the woman is and how she relates to Raiden. “From the production plants” is not established biographical information either. Her identity remains unknown; **the person remembering her is known**.

**Karlstahl is assigned words he did not say.** `f000146` says he explains that the Empire’s fall removes the justification for internment while civilians resist change. C1:p0122 is narration; p0123 is Lena speaking. Karlstahl’s response at p0124 tells her to temper her ideals. Assigning the narration to him changes his position in the argument.

**An instruction to disconnect becomes the act of disconnecting.** `f000323` says Raiden closes the Resonance. At C3:p0186 he tells Lena to close it; p0190 explicitly says she does. Preserve the request and execution separately. This small error illustrates why finding the relevant verb in a quotation does not establish the correct actor.

#### 4.2 Assertion labels are not consistently applied

Of 238 records with assertion labels, 231 are explicit, 2 reported, and 5 inferred. The distribution alone proves nothing, but it deserves attention in a novel full of broadcasts, rumors, testimony, and limited perspectives.

| Records | Problem | Better treatment |
| --- | --- | --- |
| `f000093–f000094` | Broadcast claims about invasion, abolition, and discharge become explicit attributes. | Preserve reported claims attributed to the Republic; the event of broadcasting can remain explicit. |
| `f000053` | Annette’s description of herself as a certified genius becomes an objective skill attribute. | Record self-description or remove the implied certification; the joking statement does not prove a credential. |
| `f000280–f000281` | Rei’s death and its date cite only Shin’s speech but are explicit. | Under the project’s definitions, use reported with `c006` as source. This does not accuse Shin of lying. |
| `f000101` | Findings from captured machines and a universal shutdown forecast are combined. | Separate the finding, the Republic’s forecast, and its assumptions. A forecast can be a reported/future event. The existing word “expected” is a useful qualification, but provenance remains weak. |

Do not automatically mark every dialogue event reported. `f000328` records that Shin says his brother died; the occurrence of that conversation can be explicit. Extracting the brother’s death as an independently true proposition is a different claim. Likewise, `f000125` records a zero-casualty broadcast rather than asserting that nobody died.

#### 4.3 Accumulated knowledge lacks adequate validity boundaries

`current.active_record_ids` means records not retracted or superseded, not necessarily facts still true in the present. Historical facts remaining active are not automatically errors. The problem is that some records omit enough temporal context to mislead consumers.

- `f000115` still represents Lena commanding Pleiades as current after her transfer, while `f000048` correctly calls that role former. The relationship and attribute views disagree.
- `f000196` retains “appointed a week ago” after Chapter 3 advances to half a month. It is correct relative to Chapter 2, but unsuitable as an undated current profile entry.
- `f000312` describes half a month without casualties before Kaie dies. Preserve the historical interval, but anchor it to the chapter opening rather than presenting a timeless current record.
- `f000223` records 21 deployed Juggernauts in Chapter 2’s battle. It should not become the squad’s end-of-Chapter-3 strength, nor justify computing a later strength without evidence.
- `f000113` uses the Empire’s declaration nine years earlier for a current war relationship while the model also records its fall. Distinguish the historical declaration from the ongoing conflict with the Legion.

This is partly a schema limitation. Attributes have no separate temporal field; transitions cannot target records introduced in the same delta; relationship supersedes must retain temporal_context. A state becoming obsolete within one chapter, or a current relationship becoming historical, cannot simply be fixed with an ordinary supersede. Short-term solutions include explicit time anchors and storing transient states as events. Longer-term options include validity intervals and relationship endings.

#### 4.4 Narrative order and event granularity

`f000325` cites the former captain’s final transmission at C3:p0339–p0344 but gives it narrative_order 9, before the nighttime conversation beginning at p0201. The complete story is revealed during the following day’s conversation. Mentioning the captain at p0196 does not justify moving the later account of his death forward.

`f000328` crosses a flashback boundary: it combines Lena’s question at p0258 with the brother’s identification, reported death, and search at p0311–p0321, then lists the flight and rescue in `f000329–f000331`. It should become **question about the name → childhood flashback → return to the present and confirmation/search conversation**. Revelation order matters even within a single chapter.

Conversely, Chapter 2’s `f000250–f000251` correctly follow the text in mentioning the shooting game before describing the earlier dinner. They should not automatically be reordered into world chronology. The difficulty is that one event also combines the earlier meal with later coffee and reading, making the different temporal layers hard to represent.

#### 4.5 Quotation matching falls short of semantic support

`f000248` describes resupply by Fido followed by the destruction of multiple Löwe, but its sole quotation is “Undertaker fired.” `f000240` includes a boar, jam-making, and dinner arrangements, while the quotation merely locates the characters in the kitchen. The wider source often supports the account, so these need not all be called hallucinations. **The saved evidence nevertheless does not substantiate the full claim.**

`f000247` also drops the uncertainty around Lena’s potential observer targets at p0183. Preserve the candidate status and request for confirmation, then separately record Shin’s evaluation or order. One main action per event, supported for its important quantities, reasons, actors, and outcomes, is preferable to merely making quotations longer.

#### 4.6 Relationships are thinner than event prose, and entities arrive late

Chapter 3 adds 82 records but only 4 relationships. A low count is not inherently bad; the actual omissions are the concern:

- Kaie, Kurena, and Anju lack Spearhead member_of relationships that some other members receive. Readers can infer membership from the prose, but graph queries may miss them.
- C2:p0275’s histories are not fully represented: Anju and Daiya serving together since enlistment, Kaie and Haruto joining in the same year, and Theo and Kurena spending two years with Shin and Raiden.
- Fido is repeatedly named, resupplies units, collects keepsakes, and assists games in Chapter 2, but `c027` is introduced only in Chapter 3 with a Scavenger attribute. Earlier knowledge is not automatically recovered.

Whether Fido belongs in the character category is a modeling choice, but the choice should be consistent. Since the current prompt restricts new evidence to the new chapter, Chapter 3 cannot legitimately repair Chapter 2 by inventing or recalling earlier quotations. Use a separate review or rebuild process rather than silently changing history.

`participant_ids` also mixes actors and subjects of thought. Kujo, dead for ten days, appears as a participant in Shin’s present-day countdown scene (`f000236`); Shourei appears as a participant in Shin’s final recollection (`f000333`). This can generate misleading co-presence or relationship results. Distinguish actual participants from people mentioned or remembered. Similarly, a single location_id for remote conversations should not imply everyone is physically together.

### 5. Coverage of the 23 source-first information points

These compound points were selected after reading the source and before category-by-category model inspection. **Full** means the core content is explicitly and reasonably retained; **partial** means an important component, qualification, or causal link is missing. This is neither an exhaustive inventory nor an equally weighted scoring scheme. Later discoveries, such as the misattributed old woman and missing graph edges, were reported separately rather than used to rewrite the list.

| Point | Source | Coverage | Records and gaps |
| --- | --- | --- | --- |
| C1-01 Zero casualties and institutional dehumanization | p0038–p0050 | Partial | `f000132–f000134`; the naming-to-casualty-accounting mechanism is not clearly organized. |
| C1-02 Seven deaths and the cold response to an apology | p0051–p0064 | Full | `f000135–f000136`. |
| C1-03 Opposition to Lena’s mother, rescue memory, motivation | p0076–p0088 | Partial | `f000138–f000140`; weak motivational connection. |
| C1-04 Appointment and Reaper rumors | p0099–p0125 | Full | `f000141–f000147`, `f000070`; the erroneous attribution in `f000146` is excluded as support. |
| C1-05 Shutdown prediction and uncertain Para-RAID safety | p0146–p0159 | Partial | `f000101`, `f000149`; source qualifications, knowledge gaps, and risks are thin. |
| C1-06 First contact and Lena’s judgment | p0177–p0185 | Full | `f000151–f000152`. |
| C2-01 Frozen countdown, Kujo’s death, prohibited graves | p0002–p0028 | Partial | `f000201–f000202`, `f000236`; burial restrictions appear indirectly only through Chapter 3’s `f000327`. |
| C2-02 Warning enables daily life; false reports | p0027–p0044 | Partial | `f000238–f000239`; missing causal connection to Shin’s ability. |
| C2-03 Fido’s history and respect for the remains | p0103–p0111 | Partial | `f000242`; Fido’s history is missing. |
| C2-04 Extraordinary warning and Sheep/Shepherd mystery | p0115–p0131 | Partial | `f000243`; the terminology becomes an uncertainty only in Chapter 3’s `f000336`. |
| C2-05 Lena’s tactical contribution and laser-transmission risk | p0155–p0189 | Partial | `f000247`; missing correction and risk, weakened candidate qualification. |
| C2-06 Shin’s skill and its mechanical/human costs | p0201–p0217 | Partial | `f000193`, `f000248`; costs and maintenance connection are thin. |
| C2-07 Reading quiets the sound, false illiteracy, discharge discomfort | p0234–p0285 | Partial | `f000251–f000252`; exposed excuse and atmosphere not clearly retained. |
| C3-01 Unnamed cat, Kurena’s trauma, rat cover story | p0017–p0055 | Partial | `f000318–f000319`, `f000306`; rat excuse missing. |
| C3-02 Kaie rejects collective labels and projected noble motives | p0070–p0096 | Partial | `f000320`; discrimination within the Eighty-Six and imposed meaning are compressed. |
| C3-03 Map, artillery support, institutional obstruction | p0102–p0129 | Partial | `f000321` preserves repositioning; map access and refused artillery support are missing. |
| C3-04 Marsh death, blocked recovery, Anju’s shell | p0135–p0157 | Partial | `f000322`; Anju’s subsequent shot is omitted. |
| C3-05 Inequality/name criticism and regret over cruelty | p0161–p0200 | Partial | `f000323–f000324`; reasons are thin and the disconnecting actor is wrong. |
| C3-06 Names, institutions, 561 remembered dead, contrasting feelings | p0211–p0255 | Partial | `f000299–f000300`, `f000327`; institutional function and relational distinctions are weak. |
| C3-07 Father’s ideals/recklessness, rescue, Rei’s desire to survive | p0260–p0307 | Partial | `f000329–f000331`; the father’s blind spots are omitted. |
| C3-08 Brother identity, reported death, search is not for a body | p0308–p0324 | Partial | `f000328`, `f000335`; explicit denial of a body search is missing and death labels need correction. |
| C3-09 Individual introductions, captain’s story, qualified contact | p0325–p0362 | Full | Content in `f000332`, `f000325`; the latter’s order separately needs correction. |
| C3-10 Name and scarf leave a mystery | p0363–p0365 | Full | Content in `f000333`; participant field separately needs correction. |

“Full” concerns preservation of the information point, not correctness of every associated field. The last two rows demonstrate that **good plot coverage can coexist with structural errors**.

### 6. Fixed-position check of 27 records

For each chapter and category, selection uses the first, earlier middle, and final item; the middle zero-based index is `floor((n-1)/2)`. Judgments consider the whole record and paragraph context, with quotation shortcomings noted separately. This rule was applied after reading the model and is not a blind evaluation; it prevents the report from containing only hand-picked failures. The sample reaches early, middle, and late parts of the chapters, supplemented by the targeted findings above.

| Chapter/category | Records and source | Judgment |
| --- | --- | --- |
| C1 attributes | `f000040` p0008; `f000072` p0181; `f000104` p0049 | All supported; approximate age retains “roughly” and is later superseded. |
| C1 relationships | `f000105` p0008; `f000114` p0003; `f000124` p0004 | All supported in chapter context; `f000114` would benefit from evidence independent of the broadcast. |
| C1 events | `f000125` p0003; `f000138` p0072–p0077; `f000152` p0180–p0184 | All supported by the wider text; the first two quotations cover only part of their summaries. The broadcast event does not endorse its content. |
| C2 attributes | `f000184` p0013; `f000204` p0046; `f000224` p0157–p0181 | All supported; Legion types receive multiple relevant quotations. |
| C2 relationships | `f000225` p0003–p0004; `f000230` p0075; `f000235` p0146 | All supported; Kujo’s membership is past, and remote command matches earlier context. |
| C2 events | `f000236` p0003–p0004; `f000244` p0130–p0134; `f000252` p0235–p0285 | `f000236` unsupported: a dead person is a current participant. The other two are supported by the wider text, with incomplete quoted support. |
| C3 attributes | `f000280` p0315; `f000296` p0145–p0146; `f000312` p0004 | `f000280` unsupported: reported content labeled explicit. `f000296` supported, but fuller evidence is desirable. `f000312` needs_review: correct at the opening, ambiguous as an undated end-of-chapter attribute. |
| C3 relationships | `f000313` p0311–p0313; `f000314` p0285–p0288; `f000316` p0103 | All supported; narration confirms the brother relationship, rescue direction is correct, and Transport affiliation is reasonably inferred. |
| C3 events | `f000317` p0002–p0004; `f000325` p0339–p0345; `f000333` p0364–p0365 | `f000317` supported; p0003 would support the call. `f000325` unsupported: misplaced revelation order. `f000333` unsupported: the brother is remembered rather than acting in the present. |

Unsupported includes unsupported labels, ordering, or participants; it does not mean the entire scene was invented. Needs_review identifies an interpretation or presentation boundary rather than a definite factual error.

### 7. Recommended next steps

1. **Correct definite errors first.** Reassign the old woman’s recollection to Raiden, remove the speech invented for Karlstahl, distinguish the instruction to disconnect from its execution, and restore the flashback/revelation order. Use an auditable correction or rerun workflow rather than rewriting committed history directly.
2. **Check the source of every proposition.** Separate “someone said X” from “X is true.” Preserve forecasters and assumptions. Identify the viewpoint character before attributing an inner monologue. Prioritize broadcasts, death testimony, and summaries of motives.
3. **Make key events smaller and evidence sufficient.** Avoid one record spanning an entire conversation, several temporal layers, or multiple independent revelations. Check participants, locations, and narrative order as well as descriptions.
4. **Prioritize mechanisms, abilities, motives, and relationships over further appearance details.** Add Shin’s warning/rest connection, obstructed maps and artillery, Fido’s relationship with Shin, Kaie’s rejection of collective labels, and naming/memorial practices. Literary interpretation can be an evidence-linked reading note; it should not masquerade as an explicit fact.
5. **Separate historical knowledge from current state.** Anchor relative dates and statistics now. Consider validity intervals, relationship endings, character knowledge-acquisition events, and actors versus mentioned entities later. Not every issue requires an immediate schema redesign.
6. **Compare the next version against the same source locations.** Revisit the specific defects and 23 information points, checking whether additional coverage introduces new over-inference. More records do not automatically mean better understanding.

I would preserve the existing identity history and restraint around mysteries, then improve causes and provenance. For these chapters, the most valuable additional knowledge is not another hair color: it is **how the Republic erases names, how Shin preserves them, and how Lena finally begins asking people for their own names**.

### 8. Run and verification identifiers

All three commits identify provider `deepseek` and model/response_model `deepseek-flash`. Their run IDs are `86v1-ch1`, `86v1-ch2`, and `20261102T002241Z-b272de`. The first two chapters include three documented manual evidence corrections: one quotation-mark correction and two paragraph-location corrections. The Chapter 3 commit records none. This review adds only this document and does not modify the model.

```text
model file SHA-256:
ca9e742104c5ddc8d84f4c4a4800e4fe21db930a80ae275ef368de96fefc2190
EPUB SHA-256:
452d8183147c1d20a0d474b8d0c981556b2f1bdb4bfb7151c25729f413911317
prompt SHA-256 (all three committed runs):
ed09bd6c6cb3dd138763583d18688c826d0b83c285fdbdc4ef6a3470ea1a1c76
schema SHA-256 (all three committed runs):
70e8068ec2ca9cfdce0a1e3df5cdc391a4d132ce966fdda5a2459a578a3f42fd
```

Source index: C1 = [section-004 input](../stores/86v1/inputs/section-004-d1053fa1bbdd5a16.json); C2 = [section-005 input](../stores/86v1/inputs/section-005-1f5791967938e77a.json); C3 = [section-006 input](../stores/86v1/inputs/section-006-c088eb42012207fd.json). These supporting inputs are local and may not be distributed with the repository. Format judgments refer to the [format documentation](../STORY_MODEL_FORMAT.md) and [update prompt](../src/loremark_story_lab/prompts/update_story_v2.txt).
