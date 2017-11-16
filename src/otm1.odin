import "core:os.odin";

MAGIC_VALUE :: 0x4f544d31;  //Hex for "OTM1"

Header :: struct #ordered {
    magic : u32,
    total_ms : u32,
    timing_count : u32,
}

Entry_Flags :: enum u32 {
    Complete = 1 << 1,
    NoError  = 1 << 2,
}

Entry :: struct #ordered {
    date_raw     : [2]u32, //lo, hi
    time_elapsed : u32, //In milliseconds
    flags        : Entry_Flags
}

Data :: struct {
    header : Header,
    entries : []Entry,
}

validate_as_otm1 :: proc(file_handle : os.Handle) -> (Header, bool) {
    prev, ok := os.seek(file_handle, 0, 1);
    if ok != 0 {
        return Header{}, false;
    }
    _, ok = os.seek(file_handle, 0, 0);
    if ok != 0 {
        return Header{}, false;
    }

    buf : [size_of(Header)]u8;
    _, err := os.read(file_handle, buf[..]);
    header := (cast(^Header)&buf[0])^;

    if header.magic != MAGIC_VALUE {
        os.seek(file_handle, prev, 0);
        return Header{}, false;
    } else {
        os.seek(file_handle, prev, 0);
        return header, true;
    }
}

is_entry_flag_set :: proc(data : Entry_Flags, flag : Entry_Flags) -> bool {
    return data & flag == flag;
}