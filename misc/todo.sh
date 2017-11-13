# @Author: Mikkel Hjortshoej
# @Date:   03-11-2017 00:37:11
# @Last Modified by:   Mikkel Hjortshoej
# @Last Modified time: 03-11-2017 00:55:47

find ../src/ -name '*.odin' | xargs grep -n //TODO
find ../../odin-mantle/ -name '*.odin' | xargs grep -n //TODO