/*
 *  @Name:     ctime_convert
 *  
 *  @Author:   Mikkel Hjortshoej
 *  @Email:    hoej@northwolfprod.com
 *  @Creation: 13-11-2017 17:06:40
 *
 *  @Last By:   Mikkel Hjortshoej
 *  @Last Time: 28-11-2017 22:23:34
 *  
 *  @Description:
 *      Functionality requires to convert ctime files to otm1 files
 */

import "core:os.odin";
import "core:fmt.odin";
import "core:raw.odin";

import "otm1.odin";
using import "otime_err.odin";

MAGIC_VALUE :: 0xCA5E713F; 

Entry_Flags :: enum u32 {
    Complete = 0x1,
    NoErrors = 0x2,
}

Header :: struct #ordered {
    magic : u32
}

Entry :: struct #ordered {
    date_raw     : [2]u32, //lo, hi
    flags        : u32,
    time_elapsed : u32, //In milliseconds
}

validate_as_ctime :: proc(file_handle : os.Handle) -> bool {
    _, ok := os.seek(file_handle, 0, 0);
    if ok != 0 {
        return false;
    }

    buf : [size_of(Header)]u8;
    _, err := os.read(file_handle, buf[..]);
    header := (cast(^Header)&buf[0])^;
    if header.magic != MAGIC_VALUE {
        return false;
    } else {
        return true;
    }
}

convert_to_otm1 :: proc(file_handle : os.Handle, name : string) -> (Err, otm1.Header, []otm1.Entry) {
    ///Create backup
    size, err := os.file_size(file_handle);
    if err != 0 {
        return ERR_READ_FAILED, otm1.Header{}, nil;
    }

    old_data := make([]u8, size);
    _, err = os.seek(file_handle, 0, 0);
    if err != 0 {
        return ERR_READ_FAILED, otm1.Header{}, nil;
    }
    _, err = os.read(file_handle, old_data);
    if err != 0 {
        return ERR_READ_FAILED, otm1.Header{}, nil;
    }

    str := fmt.aprintf("%s.old", name);
    h, e := os.open(str, os.O_CREATE | os.O_RDWR);
    free(str);
    if e != 0 {
        return ERR_OPEN_FAILED, otm1.Header{}, nil;
    }
    _, err = os.write(h, old_data);
    free(old_data);
    if err != 0 {
        return ERR_WRITE_FAILED, otm1.Header{}, nil;
    }

    data_start, ok := os.seek(file_handle, size_of(Header), 0);
    if ok != 0 {
        return ERR_READ_FAILED, otm1.Header{}, nil;
    }
    entries_bytes := make([]u8, size - data_start);
    _, ok = os.read(file_handle, entries_bytes);
    if ok != 0 {
        return ERR_READ_FAILED, otm1.Header{}, nil;
    }
    os.close(file_handle);
    file_handle, err = os.open(name, os.O_RDWR | os.O_TRUNC);
    if err != 0 {
        return ERR_OPEN_FAILED, otm1.Header{}, nil;
    }
    header := otm1.Header{};
    header.magic = otm1.MAGIC_VALUE;
    
    raw_entries := raw.Slice{
        &entries_bytes[0],
        len(entries_bytes) / size_of(Entry),
    };
    c_entries := transmute([]Entry)raw_entries;

    entries := make([]otm1.Entry, len(c_entries));
    for c, i in c_entries {
        entries[i].date_raw = c.date_raw;
        entries[i].time_elapsed = c.time_elapsed;

        if c.flags & u32(Entry_Flags.NoErrors) == u32(Entry_Flags.NoErrors) {
            entries[i].flags |= otm1.Entry_Flags.NoError;
        }
        if c.flags & u32(Entry_Flags.Complete) == u32(Entry_Flags.Complete) {
            entries[i].flags |= otm1.Entry_Flags.Complete;
        }
    }

    for e in entries {
        if otm1.is_entry_flag_set(e.flags, otm1.Entry_Flags.Complete) {
            header.total_ms += e.time_elapsed;
        }
        header.timing_count += 1;
    }

    return ERR_OK, header, entries;
}