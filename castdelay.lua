addon.name      = 'CastDelay';
addon.author    = 'Thorny';
addon.version   = '1.00';
addon.desc      = 'Delays casting, item usage, and ranged attacks until the player has stopped moving.';
addon.link      = 'https://github.com/ThornyFFXI/';

require('common')
local chat = require('chat')
local ffi = require('ffi')
ffi.cdef[[
    int32_t memcmp(const void* buff1, const void* buff2, size_t count);
]];

-- Tunables
local SETTINGS = {
    MAX_RETRY_DELAY = 5, --The maximum delay, in seconds, applied before an action is abandoned.
}

local currentPosition = {};
local isMoving = true;
local pendingAction;
ashita.events.register('packet_out', 'packet_out_cb', function(e)
    -- Only update position when an uninjected packet happens. Check the entire chunk to handle race conditions.
    if (not e.injected) and (ffi.C.memcmp(e.data_raw, e.chunk_data_raw, e.size) == 0) then

        --Read ahead..
        local incomingAction;
        local offset = 0;
        while (offset < e.chunk_size) do
            local id    = ashita.bits.unpack_be(e.chunk_data_raw, offset, 0, 9);
            local size  = ashita.bits.unpack_be(e.chunk_data_raw, offset, 9, 7) * 4;
            if (id == 0x15) then
                local xPosition = struct.unpack('f', e.chunk_data, offset + 0x04 + 1);
                local yPosition = struct.unpack('f', e.chunk_data, offset + 0x0C + 1);
                isMoving = (xPosition ~= currentPosition.X) or (yPosition ~= currentPosition.Y);
                currentPosition.X = xPosition;
                currentPosition.Y = yPosition;
            elseif T{0x00A, 0x00B}:contains(id) then
                pendingAction = nil;
                currentPosition = {}
            end

            if (id == 0x1A) then
                incomingAction = struct.unpack('c' .. size, e.chunk_data, offset + 1);
            end

            offset = offset + size;
        end

        if (isMoving == false) then
            -- If player isn't moving and the chunk already contains a player-created action packet, then toss out pending action.
            if incomingAction then
                pendingAction = nil;
                return;

            -- Otherwise, inject it.
            elseif pendingAction then
                if (os.clock() < (pendingAction.Time + SETTINGS.MAX_RETRY_DELAY)) then
                    AshitaCore:GetPacketManager():AddOutgoingPacket(pendingAction.Id, pendingAction.Data);
                    print(chat.header('CastDelay') .. chat.message("Action reinjected."));
                end
                pendingAction = nil;
            end
        end
    end

    if (e.id == 0x1A) and (not e.blocked) and isMoving then
        local actionType = struct.unpack('H', e.data, 0x0A+1);
        if T{0x03, 0x10}:contains(actionType) then
            pendingAction = { Id=e.id, Data=struct.unpack('c' .. e.size, e.data, 1):totable(), Time=os.clock() };
            e.blocked = true;
            print(chat.header('CastDelay') .. chat.message("Blocked action due to movement. Action will be reinjected."));
        end
    end

    if (e.id == 0x37) and (not e.blocked) and isMoving then
        pendingAction = { Id=e.id, Data=struct.unpack('c' .. e.size, e.data, 1):totable(), Time=os.clock() };
        e.blocked = true;
        print(chat.header('CastDelay') .. chat.message("Blocked action due to movement. Action will be reinjected."));
    end
end);
