# ########## 用户配置 ##########
# 设置你的Dota 2 pak01_dir.vpk目标路径
$SourceVPK = "E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota\pak01_dir.vpk"
# ############################


vpkeditcli --extract "scripts/npc/" -o "./pak01_dir/scripts/npc/" $SourceVPK
vpkeditcli --extract "scripts/shops.txt" -o "./pak01_dir/scripts/shops.txt" $SourceVPK
vpkeditcli --extract "resource/localization/abilities_english.txt" -o "./pak01_dir/resource/localization/abilities_english.txt" $SourceVPK
vpkeditcli --extract "resource/localization/abilities_schinese.txt" -o "./pak01_dir/resource/localization/abilities_schinese.txt" $SourceVPK
