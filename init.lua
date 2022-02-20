hacktool = {}

-- Are the optional dependencies enabled?
local xdecor_enabled = minetest.get_modpath("xdecor")
local unified_inventory_enabled = minetest.get_modpath("unified_inventory")
local mailbox_enabled = minetest.get_modpath("mailbox")

-- Build a list of inventories depening on the mods enabled
local inventories = {{ label = "Main", name = "main" }}
if xdecor_enabled then
	table.insert(inventories, { label = "Ender", name = "enderchest" })
end
if mailbox_enabled then
	table.insert(inventories, { label = "Mail", name = "mailbox" })
end
if unified_inventory_enabled then
	for bag_i = 1, 4 do
		table.insert(inventories, {
			label = ("Bag %i"):format(bag_i),
			name = ("bag%icontents"):format(bag_i)
		})
	end
end

-- Make the form wider if there are too many buttons
local formspec_width = math.max(8, #inventories*2)

-- Formspec contexts, to maintain the same target user while switching formspecs
local contexts = {}
local function get_target_player(user_name)
	local context = contexts[user_name]
	if not context then return end

	local player = context.target
	if not player or player:is_player() ~= true then return end

	return player
end

-- Does str start with start, if so return everything else
local function starts_with(str, start)
	local len = #start
	if str:sub(1, len) == start then
		return str:sub(len+1)
	end
end

-- Show the formspec for a given inventory to the given user
local function show_formspec(user_name, inventory_name)

	local player = get_target_player(user_name)
	if not player then return end
	
	if not inventory_name then inventory_name = "main" end

	minetest.show_formspec(
		user_name,
		"invhack.form",
		hacktool.formspec(user_name, player, inventory_name)
	)
end

-- Generate a formspec for the given inventory positioned at X, y
local function inventory_formspec(name, inv, X, y)
	if not y then y = 0 end
	if not X then X = 0 end
	local x = X
	local formspec = ""
	local size = inv:get_size(name)
	for i = 1, size, 1 do
		local stack = inv:get_stack(name, i)
		local count = stack:get_count()
		formspec = formspec .. ("item_image_button[%f,%f;1,1;%s;item:%s:%i;\n\n\b\b\b%s]"):format(
				x, y,
				stack:get_name(),
				name, i,
				count > 0 and tostring(count) or ""
			)
		x = x + 1
		if x >= X + 8 then
			x = X
			y = y + 1
		end
	end
	return formspec, y
end
local grab = false
-- Generate the entire formspec for this tool
hacktool.formspec = function(user_name, player, inventory_name)
	local formspec = ("size[8,5.4]checkbox[0,5;grab;Grab item;"..tostring(grab).."]")

	for i, inv_def in ipairs(inventories) do
		formspec = formspec .. ("button[%f,4.2;1,1;inventory:%s;%s]"):format((i - 1) * 1, inv_def.name, inv_def.label)
	end

	formspec = formspec .. inventory_formspec(inventory_name, player:get_inventory(), 0, 0)
--formspec = formspec .. inventory_formspec(inventory_name, player:get_inventory(), (formspec_width - 8) / 1, 0)
	return formspec
end

minetest.register_privilege("invhack", {
	description = "Allows check sus players' inventories",
	give_to_singleplayer = true,
})

-- Respond to a button press on the formspec
minetest.register_on_player_receive_fields(function(user, form, pressed)
	-- Not our concern, exit
	if form ~= "invhack.form" then return end

	local user_name = user:get_player_name()

	-- Exit
	if pressed.quit then
		contexts[user_name] = nil
		return
	end

	-- No privs, this should not happen, but might
	if not minetest.check_player_privs(user_name, {invhack=true}) then
		minetest.chat_send_player(user_name, "Missing privilege: invhack")
		return
	end

	-- Check if target player exists
	local player = get_target_player(user_name)
	if not player then
		contexts[user_name] = nil
		minetest.chat_send_player(user_name, "The formspec context is empty or the player is offline")
		return
	end

	-- Figure out which action is intended
	local selected_inventory
	local selected_item
	for name,_ in pairs(pressed) do
		selected_inventory = starts_with(name, "inventory:")
		if selected_inventory then break end

		selected_item = starts_with(name, "item:")
		if selected_item then break end
	end
if pressed.grab then
grab = not grab
end
	-- Move an item from the target players inventory to the invhack user's inventory
	if selected_item then
		-- Split apart the button name to get the inventory and position
		local separator_index = selected_item:find(":", 1, true)
		local inventory_name = selected_item:sub(1, separator_index - 1)
		local stack_index = tonumber(selected_item:sub(separator_index + 1))

		-- Get the stack of the target player's inventory, if empty do nothing
		local target_inventory = player:get_inventory()
		local stack = target_inventory:get_stack(inventory_name, stack_index)
		if stack:get_count() == 0 then
			return
		end

		-- Find the first empty slot in the invhack user's inventory
		local user_inventory = user:get_inventory()
		local empty_slot = 0
		local empty_found = false
		for search_index = 1, 32, 1 do
			empty_slot = search_index
			if user_inventory:get_stack("main", search_index):get_count() == 0 then
				empty_found = true
				break
			end
		end

		-- Warn them if their inventory is full
		if not empty_found then
			minetest.chat_send_player(user_name, "Error: Your inventory is full")
			return
		end

		-- Move the item into the invhack user's inventory
		user_inventory:set_stack("main", empty_slot, stack)
		-- Remove the item from the target player's inventory
        if grab == true then
		target_inventory:set_stack(inventory_name, stack_index, nil)
        end
		-- Trigger formspec reload - see below
		selected_inventory = inventory_name
	end

	-- Switch the formspec to the selected inventory
	if selected_inventory then
		show_formspec(user_name, selected_inventory)
	end
end)

minetest.register_tool("invhack:tool", {
	description = "Inventory hack tool",
	range = 15,
	--inventory_image = "hacktool_inv.png",
	inventory_image = "[png:iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAyRpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADw/eHBhY2tldCBiZWdpbj0i77u/IiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8+IDx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IkFkb2JlIFhNUCBDb3JlIDUuMy1jMDExIDY2LjE0NTY2MSwgMjAxMi8wMi8wNi0xNDo1NjoyNyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIgeG1sbnM6c3RSZWY9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZVJlZiMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIENTNiAoTWFjaW50b3NoKSIgeG1wTU06SW5zdGFuY2VJRD0ieG1wLmlpZDo2N0I5QTQxQTBERDExMUU1OTFDQkRCRURBODFERDJGRSIgeG1wTU06RG9jdW1lbnRJRD0ieG1wLmRpZDo2N0I5QTQxQjBERDExMUU1OTFDQkRCRURBODFERDJGRSI+IDx4bXBNTTpEZXJpdmVkRnJvbSBzdFJlZjppbnN0YW5jZUlEPSJ4bXAuaWlkOjM1QjMyOUQxMEREMTExRTU5MUNCREJFREE4MUREMkZFIiBzdFJlZjpkb2N1bWVudElEPSJ4bXAuZGlkOjM1QjMyOUQyMEREMTExRTU5MUNCREJFREE4MUREMkZFIi8+IDwvcmRmOkRlc2NyaXB0aW9uPiA8L3JkZjpSREY+IDwveDp4bXBtZXRhPiA8P3hwYWNrZXQgZW5kPSJyIj8+qhktZwAAAWlJREFUeNrEVwsOgyAMFeLl9MB6PGadTbC2paWyNSE6HLxHPw9IpZTJYyklccAxV5qcliwENNAomTwC3DNO9EAvsNcTefqz5ZGrt8yVPQO2bQOX3hr0hQjSHOAItCrlGNOdC3Nj0O9zAJkynhlCVPXAvu83ECAhgeF3jpgaIppU16BSvi/n80i08502zqTv1+8nFteJJCQQNCAmEagXUPU9cFQd4EoM3AkNw1OHqScnZi00MDnGDydtTc4lL5cfqhJCJVDgwF4Q2w05F3vBLy/4hWhZFrH0tJL0kM+adNK4YQJydS/FeF1XdUueLW6U8qElTuY4aVqgCQ001AJNmDQM04EEXY+rfWMbNoeAhqGONcnyd84DnCrif7ishkqBfnhK54RoEqaaRA2slVpLAV33AuoJix7UBDQPDDkV16QuEiVMQBImbvWehEyRu6ELSAhF9oJbt+XQxUQDD0tvjxDRurbcA6z2EWAAYmcOt9YFCGEAAAAASUVORK5CYII=",
	groups = {not_in_creative_inventory=1},
	on_use = function(itemstack, user, pointed_thing)
		local user_name = user:get_player_name()

		if not minetest.check_player_privs(user_name, {invhack=true}) then
			minetest.chat_send_player(user_name, "Missing privilege: invhack")
			return
		end

		if pointed_thing.type ~= "object" then return end
		local player = pointed_thing.ref
		if player:is_player() == false then return end

		contexts[user_name] = {target=player}

		show_formspec(user_name)

		return itemstack
	end,
})

minetest.register_chatcommand("invhack", {
  description = "View player's inventory",
  params = "<playername>",
  privs = {invhack=true},
  func = function(name, param)
local player = minetest.get_player_by_name(param)
local user_name = name
	contexts[user_name] = {target=player}
	if not player then return end
	
	if not inventory_name then inventory_name = "main" end

	minetest.show_formspec(
		user_name,
		"invhack.form",
		hacktool.formspec(name, player, inventory_name)
	)
  end,
})
