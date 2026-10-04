class_name LfeCraftingGrid
extends RefCounted

var inventory: LfeInventory
var size: int
var context: String
var _recipes: LfeRecipeCatalog

func _init(catalog: LfeBlockCatalog, recipes: LfeRecipeCatalog, grid_size: int = 2) -> void:
	size=grid_size
	context="workbench" if size==3 else "hand"
	inventory=LfeInventory.new(catalog,size*size)
	_recipes=recipes

func preview() -> Dictionary:
	return _recipes.match_grid(inventory,size,context)

# Re-match inside the transaction. Preview outputs are never material inventories.
func take(destination: LfeInventory, expected_recipe: String = "") -> bool:
	if destination==inventory or destination._catalog!=inventory._catalog:return false
	var match: Dictionary = preview()
	if match.is_empty() or (not expected_recipe.is_empty() and match["recipe"]!=expected_recipe):return false
	var next_grid: LfeInventory = LfeInventory.new(inventory._catalog,inventory.capacity())
	var next_destination: LfeInventory = LfeInventory.new(destination._catalog,destination.capacity(),destination._restrictions)
	next_grid.restore(inventory.snapshot());next_destination.restore(destination.snapshot())
	for entry: Dictionary in match["consumption"]:
		if not LfeItemTransactions.remove(next_grid,int(entry["slot"]),int(entry["quantity"])):return false
	if not LfeRecipeTransactions.outputs(next_destination,match["outputs"]):return false
	if not LfeWorldResourceState.unique_instances(next_grid.snapshot()+next_destination.snapshot()):return false
	inventory.restore(next_grid.snapshot());destination.restore(next_destination.snapshot())
	return true

# Return everything or retain everything. A full backpack cannot eat staging.
func release(destination: LfeInventory) -> bool:
	if destination==inventory or destination._catalog!=inventory._catalog:return false
	var next_grid: LfeInventory = LfeInventory.new(inventory._catalog,inventory.capacity())
	var next_destination: LfeInventory = LfeInventory.new(destination._catalog,destination.capacity(),destination._restrictions)
	next_grid.restore(inventory.snapshot());next_destination.restore(destination.snapshot())
	for slot: int in next_grid.capacity():
		var stack: Dictionary = next_grid.stack_at(slot)
		if not stack.is_empty() and LfeItemTransactions.transfer(next_grid,slot,next_destination,int(stack["quantity"]))!=int(stack["quantity"]):return false
	if not LfeWorldResourceState.unique_instances(next_grid.snapshot()+next_destination.snapshot()):return false
	inventory.restore(next_grid.snapshot());destination.restore(next_destination.snapshot())
	return true
