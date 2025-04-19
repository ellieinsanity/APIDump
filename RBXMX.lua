
--[[
	RBXMX by einsteinK
	
	Has a small XML parser from somewhere on Lua.org that works now.
	Allows (un)serializing ROBLOX instances (using the (old) XML format)
	
	Returns a table with 2 methods:
	- Serialize({instance1,instance2,...}): Serializes the instances to XML and returns it (to .rbxmx)
	- Unserialize(str): Reverses the process and returns a table with the instances in the XML (from .rbxmx)
	When the framework sees that rbxmx.lua is present, it'll also add 2 functions to the Globals table:
	- saveinstance(file,instance): Serializes an instance and saves it to the file (in .rbxmx format)
	- loadinstance(file): Returns the (first) instance saved in the file (in .rbxmx format, otherwise errors)
	- saveplace(file): Like saveinstance for creating a .rbxlx so it's easier to feel good of yourself by stealing places
		(Only saves contents of: Workspace,Lighting,StarterPack,StarterGui,ReplicatedStorage,StarterPlayer,Teams and Chat)
	AGAIN: THIS ONLY SUPPORTS THE XML FORMAT (.rbxmx and .rbxlx) AND CAN ONLY SAVE/LOAD IN THIS FORMAT
	(well, saveinstance/loadinstance can be used on any file, even .exe, as long as the content are .rbxmx)
	
--]]

local function parseargs(s)
	local arg = {}
	string.gsub(s, "([%-%w]+)=([\"'])(.-)%2", function (w, _, a)
		arg[w] = a
	end)
	return arg
end

local function parseXML(s)
	local stack = {}
	local top = {}
	table.insert(stack, top)
	local ni,c,label,xarg, empty
	local i, j = 1, 1
	while true do
		ni,j,c,label,xarg, empty = string.find(s, "<(%/?)([%w:]+)(.-)(%/?)>", i)
		if not ni then break end
		local text = string.sub(s, i, ni-1)
		if not string.find(text, "^%s*$") then
			table.insert(top, text)
		end
		if empty == "/" then  -- empty element tag
			table.insert(top, {label=label, args=parseargs(xarg), empty=1})
		elseif c == "" then   -- start tag
			top = {label=label, args=parseargs(xarg)}
			table.insert(stack, top)   -- new level
		else  -- end tag
			local toclose = table.remove(stack)  -- remove top
			top = stack[#stack]
			if #stack < 1 then
				error("nothing to close with "..label)
			end
			if toclose.label ~= label then
				error("trying to close "..toclose.label.." with "..label)
			end
			table.insert(top, toclose)
		end
		i = j+1
	end
	local text = string.sub(s, i)
	if not string.find(text, "^%s*$") then
		table.insert(stack[#stack], text)
	end
	if #stack > 1 then
		error("unclosed "..stack[#stack].label)
	end return stack[1]
end

local patterns = {
	Item = '<Item class="%s" referent="%s">\n';
	Property = '<%s name="%s">%s</%s>\n';
	CFrame = ([[<X>%f</X><Y>%f</Y><Z>%f</Z>
		<R00>%f</R00><R01>%f</R01><R02>%f</R02>
		<R10>%f</R10><R11>%f</R11><R12>%f</R12>
		<R20>%f</R20><R21>%f</R21><R22>%f</R22>]]):gsub("%s+","");
	Vector2 = [[<X>%f</X><Y>%f</Y>]];
	Vector3 = [[<X>%f</X><Y>%f</Y><Z>%f</Z>]];
	UDim2 = [[<XS>%f</XS><XO>%d</XO><YS>%f</YS><YO>%d</YO>]];
	Rect2D = [[<min><X>%f</X><Y>%f</Y></min><max><X>%f</X><Y>%f</Y></max>]];
} local classP,classes = {},{}

local AD,_ad = "https://raw.githubusercontent.com/ellieinsanity/APIDump/refs/heads/main/main"
_ad,AD = pcall(game.HttpGet,game,AD,true)
if not _ad then
	warn("Couldn't fetch JSON from Anaminus, falling back to api.txt")
	_ad,AD = pcall(readfile,"api.txt")
	if not _ad then error("Couldn't get the API in JSON format",0) end
end

local enums = {}
local function realTyp(typ)
	if typ == "Object" then
		return "Ref"
	end return typ
end

local props
for line in AD:gmatch("[^\n]+") do
	if line:find("^Class") then
		local name,parent = line:match("^Class (%w+)[%s:]*(%w*)")
		classes[name] = {Name=name,Parent=parent,Properties={}}
		props = classes[name].Properties
	elseif line:find("^Enum") then
		enums[line:match("^Enum (%w+)")],props = true
	elseif props and line:find("^\tProperty") then
		local typ,name,hmm = line:match("^\tProperty (%w+) %w+%.(%S+)(.*)$")
		if not hmm:find("%[") then props[name] = realTyp(typ) end
	end
end
for k,v in pairs(classes) do
	v.Parent = classes[v.Parent]
end

-- Some properties are useless to save
classes.Instance.Properties.Parent = nil
classes.Instance.Properties.Archivable = nil
classes.BasePart.Properties.Position = nil
classes.BasePart.Properties.Velocity = nil
classes.BasePart.Properties.RotVelocity = nil

classes.BasePart.Properties.CustomPhysicalProperties = nil -- TODO

local function classProps(class)
	if classP[class] then return classP[class] end
	local res,C = {},classes[class]
	while C do
		for k,v in pairs(C.Properties) do
			res[k] = v
		end C = C.Parent
	end classP[class] = res return res
end

local function properties(obj)
	local props,keys = classProps(obj.ClassName),{}
	for k,v in pairs(props) do
		table.insert(keys,k)
	end local i = 0
	return function() i=i+1
		local key = keys[i]
		if not key then return end
		return props[key],key,obj[key]
	end
end

for a,b,c in properties(Instance.new("TextButton")) do
	print(a,b,c)
end

local serialize
local function serializeInstance(obj,ref,tabs)
	if obj.ClassName == "" then return "" end
	if obj.ClassName == "Terrain" then return "" end
	local res = {("\t"):rep(tabs),patterns.Item:format(obj.ClassName,ref[obj]),("\t"):rep(tabs+1),"<Properties>\n"}
	--[[if obj:IsA("FormFactorPart") then
		res[#res+1] = ("\t"):rep(tabs+2)
		res[#res+1] = patterns.Property:format("a","FormFactor",serialize(obj.FormFactor,"FormFactor"),"a")
	end]]
	for typ,prop,val in properties(obj) do
		if prop ~= "FormFactor" and val ~= nil then
			if --[[val ~= "" and]] (typ ~= "Ref" or typ == "Ref" and ref[val]) then
				res[#res+1] = ("\t"):rep(tabs+2)
				local t = (typ == "Content" or typ == "Ref") and typ or 'a'
				res[#res+1] = patterns.Property:format(t,prop,serialize(val,typ,ref,prop),t)
			end
		end
	end res[#res+1] = ("\t"):rep(tabs+1)
	res[#res+1] = "</Properties>\n"
	for k,v in pairs(obj:GetChildren()) do
		if not v:IsA("PartOperation") and not v:IsA("MeshPart") then
			res[#res+1] = serializeInstance(v,ref,tabs+1)
		end
	end res[#res+1] = ("\t"):rep(tabs)
	res[#res+1] = "</Item>\n"
	return table.concat(res)
end

local char = {
	["<"] = "&lt;";
	[">"] = "&gt;";
}

local hex = {}
do
	local idk = {[0]=0,1,2,3,4,5,6,7,8,9,"A","B","C","D","E","F"}
	for i=0,255 do
		hex[i] = idk[math.floor(i/16)]..idk[i%16]
	end
end

function serialize(val,typ,ref,prop)
	if prop == "Rotation" and typ == "Vector3" then
		local x,y,z = val.X,val.Y,val.Z
		x = x < -179.99999 and 180 or x > 179.99999 and 180 or x
		y = y < -179.99999 and 180 or y > 179.99999 and 180 or y
		z = z < -179.99999 and 180 or z > 179.99999 and 180 or z
		return patterns.Vector3:format(x,y,z)
	end
	if typ == "Ref" then
		return ref[val]
	elseif enums[typ] then
		return val.Value
	elseif typ == "string" then
		return val:gsub("[<>]",char)
	elseif typ == "CoordinateFrame" then
		local comps = {val:components()}
		for i=4,12 do local v = comps[i]
			if v < 0.00001 and v > -0.00001 then comps[i] = 0 end
			if v < -0.99999 then comps[i] = -1 end
			if v > 0.99999 then comps[i] = 1 end
		end return patterns.CFrame:format(unpack(comps))
	elseif typ == "Vector2" then
		return patterns.Vector2:format(val.X,val.Y)
	elseif typ == "Vector3" then
		return patterns.Vector3:format(val.X,val.Y,val.Z)
	elseif typ == "UDim2" then
		return patterns.UDim2:format(val.X.Scale,val.X.Offset,val.Y.Scale,val.Y.Offset)
	elseif typ == "Rect2D" then
		return patterns.Rect2D:format(val.Min.X,val.Min.Y,val.Max.X,val.Max.Y)
	elseif typ == "Content" then
		return "<url>"..val.."</url>"
	elseif typ == "BrickColor" then
		return val.Number
	elseif typ == "int" or typ == "float" or typ == "double" or typ == "bool" then
		return tostring(val)
	elseif typ == "Color3" then
		local r,g,b = val.r*255,val.g*255,val.b*255
		r,g,b = math.floor(r),math.floor(g),math.floor(b)
		return tonumber("FF"..hex[r]..hex[g]..hex[b],16)
	elseif typ == "ColorSequence" or typ == "NumberSequence" or typ == "NumberRange" then
		return tostring(val)
	elseif typ == "PhysicalProperties" then
		--[[
			<PhysicalProperties name="CustomPhysicalProperties">
				<CustomPhysics>false</CustomPhysics>
			</PhysicalProperties>]]
		error("TODO",0)
	end error("Unknown property type: "..typ,0)
end

local function buildRef(obj,ref)
	ref[obj],ref[1] = ref[1],ref[1] + 1
	for k,v in pairs(obj:GetChildren()) do
		buildRef(v,ref)
	end return ref
end
local function Serialize(model)
	if typeof(model) == "Instance" then model = {model} end
	local res,ref = {'<roblox version="4">\n'},{1}
	for i=1,#model do
		res[i+1] = serializeInstance(model[i],buildRef(model[i],ref),1)
	end res[#res+1] = '</roblox>' return table.concat(res)
	--[[return table.concat{'<roblox version="4">\n';
		serializeInstance(model,buildRef(model,{1}),1);
		'</roblox>'
	}]]
end

local cfProps = {"X","Y","Z","R00","R01","R02","R10","R11","R12","R20","R21","R22"}
local bcProps = {Head=true,Torso=true,LeftArm=true,RightArm=true,LeftLeg=true,RightLeg=true,Brick=true}
local function parseValue(item,ref,classname)
	local prop = classes[classname]
	while prop do
		local p = prop.Properties[item.args.name]
		if p then prop = p break end
		prop = prop.Parent
	end if not prop then return end
	local first = item[1]
	if prop == "string" then return first end
	if prop == "bool" then return first=="true" end
	if prop == "int" then return tonumber(first) end
	if prop == "float" then return tonumber(first) end
	if prop == "double" then return tonumber(first) end
	if prop == "Ref" then return {tonumber(first)} end
	if prop == "BrickColor" then return BrickColor.new(first) end
	if prop == "Color3" then
		-- definitely broken
		local eh = first:gmatch("[^%s,]+")
		return Color3.new(eh(),eh(),eh())
	end
	if prop == "Vector2" or prop == "Vector3" or prop == "CoordinateFrame" or prop == "UDim2" then
		local eh = {}
		for i=1,#item do
			eh[item[i].label] = tonumber(item[i][1]) or item[i][1]
		end local idk = {}
		if prop == "CoordinateFrame" then
			for k,v in pairs(cfProps) do
				idk[k] = eh[v]
			end return CFrame.new(unpack(idk))
		elseif prop == "Vector2" then
			return Vector2.new(eh.X,eh.Y)
		elseif prop == "Vector3" then
			return Vector3.new(eh.X,eh.Y,eh.Z)
		elseif prop == "UDim2" then
			return UDim2.new(eh.XS,eh.XO,eh.YS,eh.YO)
		end
	end
	if prop == "Content" then
		assert(first.label == "url","Idk how to handle non-url Content")
		return first[1]
	end
	if enums[prop] then return tonumber(first) end
	error("Unknown property type:"..prop,0)
end
local function parseProps(tab,ref,classname)
	local res = {}
	for i=1,#tab do
		local item = tab[i]
		local name = item.args.name
		if name then
			res[name] = parseValue(item,ref,classname)
		end
	end return res
end
local function parseItems(tab,ref,toRef,folderForError)
	local res,props = {}
	for i=1,#tab do
		local item = tab[i]
		if item.label == "Properties" then
			props = item
		elseif item.label == "Item" then
			local suc,obj = pcall(Instance.new,item.args.class)
			if not suc and folderForError then
				suc,obj = true,Instance.new("Folder")
				warn("Couldn't create an instance of",item.args.class..", using a folder instead")
			end
			if suc then
				if item.args.referent then
					ref[tonumber(item.args.referent)] = obj
				end res[#res+1] = obj
				local childs,properties = parseItems(item,ref,toRef,folderForError)
				for i=1,#childs do
					childs[i].Parent = obj
				end
				for k,v in pairs(properties) do
					if type(v) == "table" then
						toRef[#toRef+1] = {obj,k,v[1]}
					else
						if not pcall(function() obj[k] = v end) then
							warn("Couldn't set",obj.ClassName.."."..k,"to",typeof(v),v)
						end
					end
				end
			elseif item.args.class ~= "Status" then
				warn("Couldn't create an instance of",item.args.class)
			end
		end
	end
	props = props and parseProps(props,ref,tab.args.class)
	return res,props
end
local function Unserialize(str,folderForError)
	if str:sub(1,8) ~= "<roblox " then
		error("I only support the XML format...",0)
	end --error("Soon (TM)",0)
	local parsed = parseXML(str)[1]
	assert(parsed.label == "roblox","Doesn't start with <roblox> tag")
	local ref,toRef = {},{} local objects = parseItems(parsed,ref,toRef,folderForError)
	for k,v in pairs(toRef) do v[1][v[2]] = ref[v[3]] end return objects
end

return {
	Serialize = Serialize;
	Unserialize = Unserialize;
}
