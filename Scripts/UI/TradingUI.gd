extends Control

@onready var inventory = get_node("/root/World/Player/Inventory") # Should find player dynamically
@onready var label = $Panel/Label

func _ready():
    # Attempt to find inventory if not direct path
    if not inventory:
        var player = get_tree().get_first_node_in_group("player")
        if player:
            inventory = player.get_node("Inventory")

func open():
    visible = true
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func close():
    visible = false
    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_close_button_pressed():
    close()

func _on_trade_wood_coal_pressed():
    # Cost: 4 Wood (ID 4), Reward: 1 Coal (ID 5)
    trade(4, 4, 5, 1)

func _on_trade_coal_iron_pressed():
    # Cost: 2 Coal (ID 5), Reward: 1 Iron (ID 6)
    trade(5, 2, 6, 1)

func trade(cost_id: int, cost_amount: int, reward_id: int, reward_amount: int):
    if not inventory: return
    
    # Check cost
    if inventory.has_item(cost_id, cost_amount):
        inventory.remove_item(cost_id, cost_amount)
        inventory.add_item(reward_id, reward_amount)
        # Feedback
        label.text = "Trade Successful!"
    else:
        label.text = "Not enough items!"
