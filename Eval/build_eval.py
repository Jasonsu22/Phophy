"""Builds Eval/eval.json, the search test set, from the Flickr 1K test split.

Run: python3 Eval/build_eval.py path/to/test_1k_flickr.csv
Ground truth is by original file name, so the app can match photos in its
library whatever their local IDs.
"""
import csv, json, random, re, sys

rows = list(csv.DictReader(open(sys.argv[1])))
caps = {r["filename"]: json.loads(r["raw"]) for r in rows}
files = [r["filename"] for r in rows]

# Short, user-style concept searches. (english, chinese, typo, pattern over the 5 captions)
CONCEPTS = [
    ("dog", "狗", "dgo", r"\b(dogs?|pupp(y|ies)|terriers?|retrievers?|poodles?|collies?|beagles?|labradors?)\b"),
    ("bicycle", "自行车", "bicyle", r"\b(bikes?|bicycles?|cyclists?|bikers?|bmx)\b"),
    ("beach", "海滩", "baech", r"\b(beach|beaches|shore|seashore)\b"),
    ("snow", "雪地", "snwo", r"\bsnow"),
    ("guitar", "吉他", "gutiar", r"\bguitars?\b"),
    ("soccer", "足球", "socer", r"\bsoccer\b"),
    ("baseball", "棒球", "basebal", r"\bbaseball\b"),
    ("basketball", "篮球", "basketbal", r"\bbasketball\b"),
    ("mountain", "山", "moutain", r"\bmountains?\b"),
    ("kitchen", "厨房", "kichen", r"\bkitchens?\b"),
    ("restaurant", "餐厅", "resturant", r"\brestaurants?\b"),
    ("construction worker", "建筑工人", "constrcution worker", r"\bconstruction\b"),
    ("baby", "婴儿", "babby", r"\b(baby|babies|infants?|toddlers?)\b"),
    ("stage", "舞台", "stgae", r"\bstage\b"),
    ("car", "汽车", "carr", r"\bcars?\b"),
    ("lake", "湖", "laek", r"\blakes?\b"),
    ("boat", "船", "baot", r"\b(boats?|kayaks?|canoes?|rafts?)\b"),
    ("horse", "马", "hrose", r"\bhorses?\b"),
    ("swimming", "游泳", "swiming", r"\bswim"),
    ("skateboard", "滑板", "skatebord", r"skateboard"),
    ("wedding", "婚礼", "weding", r"\b(weddings?|brides?|grooms?)\b"),
    ("umbrella", "雨伞", "umbrela", r"\bumbrellas?\b"),
    ("crowd", "人群", "crwod", r"\bcrowd"),
    ("sunglasses", "墨镜", "sunglases", r"\bsunglasses\b"),
    ("market", "市场", "markt", r"\bmarkets?\b"),
    ("bench", "长椅", "bnech", r"\bbench"),
    ("microphone", "麦克风", "microphnoe", r"\b(microphones?|mic)\b"),
    ("drums", "打鼓", "drusm", r"\b(drums?|drummer)\b"),
    ("bridge", "桥", "brigde", r"\bbridges?\b"),
    ("rock climbing", "攀岩", "rock climbnig", r"\bclimb"),
    ("cat", "猫", "cta", r"\b(cats?|kittens?)\b"),
    ("bird", "鸟", "brid", r"\b(birds?|seagulls?|pigeons?|ducks?)\b"),
    ("train", "火车", "trian", r"\b(trains?|subway)\b"),
    ("flag", "旗帜", "falg", r"\bflags?\b"),
    ("painting", "画画", "paintnig", r"\bpaint"),
    ("motorcycle", "摩托车", "motorcyle", r"\b(motorcycles?|motorbikes?)\b"),
    ("tennis", "网球", "tenis", r"\btennis\b"),
    ("surfing", "冲浪", "surfnig", r"\bsurf"),
    ("graffiti", "涂鸦", "grafitti", r"\bgraffiti\b"),
    ("police", "警察", "polcie", r"\b(police|policemen|policeman|cops?)\b"),
    ("skiing", "滑雪", "skiign", r"\b(ski|skis|skier|skiers|skiing)\b"),
    ("dancing", "跳舞", "dancnig", r"\bdanc"),
    ("fountain", "喷泉", "fountian", r"\bfountains?\b"),
    ("rodeo", "牛仔竞技", "rodoe", r"\b(rodeo|bull|bulls)\b"),
    ("wine", "葡萄酒", "wien", r"\bwine\b"),
]

# Full-sentence searches translated by hand (index into the CSV, Chinese).
CHINESE_SENTENCES = [
    (331, "一个红头发留着脏辫的男人坐着弹木吉他"),
    (970, "一只橘色小猫咬了金发小孩的鼻子"),
    (154, "一男一女骑自行车穿过荒野，远处是起伏的山丘和蓝天"),
    (404, "穿黑夹克的男人站在砖砌店面前"),
    (666, "穿粉色外套的小女孩和两个穿同款衣服的姐妹走在路上"),
    (49, "穿牛仔裤的老人在海滩上扔一个红色小球"),
    (74, "额头上戴着泳镜的小女孩在泳池里玩水"),
    (840, "穿白衬衫的男人对着麦克风弹白色吉他"),
    (548, "一群人在街上表演整齐的武术"),
    (96, "三个建筑工人在墙边的空地上挖坑"),
    (374, "雨天很多人打着伞站在有石像的喷泉旁"),
    (596, "公园里三个孩子在玩健身器材"),
    (59, "两个戴帽子拄拐杖的男人站在水边的逆光剪影"),
    (931, "牛仔竞技中一头公牛冲向一个男人"),
    (519, "一个有纹身穿靴子的女人抬起腿"),
    (219, "两个穿白衣服的人在粉刷砖墙"),
    (38, "穿黑T恤的女孩在厨房里拿着一个小披萨"),
    (88, "金发女人在昏暗的餐厅里倒葡萄酒"),
    (444, "一个小孩从后面抱着更小的孩子"),
    (428, "一只黑白相间的狗在雪地里玩橙色的球"),
    (71, "穿绿裙子的女人坐在一把破旧的绿黄色椅子上"),
    (246, "小男孩坐在女孩腿上指着什么东西"),
    (92, "女孩在河岸上奔跑跳跃"),
    (564, "穿哥特洛丽塔服装参加漫展的年轻女人"),
    (434, "戴头巾的男人和两个警察站在白色帐篷前"),
    (60, "穿紧身衣的杂技演员被托举起来"),
    (846, "男人骑自行车经过画着和平手势涂鸦的墙"),
    (579, "三只棕白色的狗互相咬着玩"),
    (126, "短黑发的女人抱着穿粉色衣服含奶嘴的婴儿"),
    (228, "人们聚在白色帐篷下坐在桌边"),
]

def matches(pattern):
    rx = re.compile(pattern, re.I)
    return [f for f in files if sum(bool(rx.search(c)) for c in caps[f]) >= 2]

sets = []
concept_en, concept_zh, concept_typo = [], [], []
for en, zh, typo, pattern in CONCEPTS:
    relevant = matches(pattern)
    if len(relevant) < 3:
        continue
    concept_en.append({"q": en, "relevant": relevant})
    concept_zh.append({"q": zh, "relevant": relevant})
    concept_typo.append({"q": typo, "relevant": relevant})
sets.append({"name": "Objects and scenes", "kind": "multi", "queries": concept_en})
sets.append({"name": "Objects and scenes, Chinese", "kind": "multi", "queries": concept_zh})
sets.append({"name": "Objects and scenes, typos", "kind": "multi", "queries": concept_typo})

random.seed(1)
sample = random.sample(range(len(files)), 200)
sets.append({"name": "Detailed descriptions", "kind": "single",
             "queries": [{"q": caps[files[i]][0].rstrip("."), "relevant": [files[i]]} for i in sample]})
sets.append({"name": "Detailed descriptions, Chinese", "kind": "single",
             "queries": [{"q": zh, "relevant": [files[i]]} for i, zh in CHINESE_SENTENCES]})

json.dump({"library": "Flickr30k 1K test", "sets": sets}, open("Eval/eval.json", "w"), ensure_ascii=False, indent=1)
for s in sets:
    print(s["name"], len(s["queries"]))
