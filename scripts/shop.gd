class_name Shop
extends Resource
## What a shopkeeper sells. Put up to 18 items in `items` (6 wide x 3 tall).

@export var title := "SHOP"
@export var items: Array[Item] = []
## Items this shopkeeper will buy from players (each pays its own Sell Price). Empty = buys nothing.
@export var buys: Array[Item] = []
