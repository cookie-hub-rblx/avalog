-- Rules shared by the client and server for saved outfits.
-- MAX_OUTFITS and MAX_NAME_BYTES must match the limits in config.zap.

local Outfits = {
	MAX_OUTFITS = 20,
	MAX_NAME_BYTES = 40,
}

-- Cuts a string to at most MaxBytes without splitting a UTF-8 character.
local function TruncateUtf8(Text: string, MaxBytes: number): string
	if #Text <= MaxBytes then
		return Text
	end

	local Cut = 0
	for Position, _ in utf8.codes(Text) do
		local NextPosition = utf8.offset(Text, 2, Position) or (#Text + 1)
		if NextPosition - 1 > MaxBytes then
			break
		end
		Cut = NextPosition - 1
	end

	return string.sub(Text, 1, Cut)
end

-- Trims, collapses whitespace, drops control characters and invalid UTF-8,
-- then shortens the name to the byte limit. Returns "" when nothing is left.
function Outfits.CleanName(Name: string?): string
	if type(Name) ~= "string" then
		return ""
	end

	if utf8.len(Name) == nil then
		Name = string.gsub(Name, "[\128-\255]", "")
	end

	Name = string.gsub(Name, "%c", " ")
	Name = string.gsub(Name, "%s+", " ")
	Name = string.match(Name, "^%s*(.-)%s*$") or ""

	return TruncateUtf8(Name, Outfits.MAX_NAME_BYTES)
end

return Outfits
