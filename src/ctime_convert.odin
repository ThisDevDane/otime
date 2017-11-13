/*
 *  @Name:     ctime_convert
 *  
 *  @Author:   Mikkel Hjortshoej
 *  @Email:    hoej@northwolfprod.com
 *  @Creation: 13-11-2017 17:06:40
 *
 *  @Last By:   Mikkel Hjortshoej
 *  @Last Time: 13-11-2017 18:26:47
 *  
 *  @Description:
 *      Functionality requires to convert ctime files to otm1 files
 */

import "core:os.odin";
import "core:fmt.odin";
import "core:raw.odin";

import "otime.odin";

CTIME_MAGIC_VALUE :: 0xCA5E713F; 

Ctime_Entry_Flags :: enum u32 {
    Complete = 0x1,
    NoErrors = 0x2,
}

Ctime_Header :: struct #ordered {
    magic : u32
}

Ctime_Entry :: struct #ordered {
    date_raw     : [2]u32, //lo, hi
    flags        : u32,
    time_elapsed : u32, //In milliseconds
}

validate_as_ctime :: proc(file : ^otime.File) -> bool {
    _, ok := os.seek(file.handle, 0, 0);
    if ok != 0 {
        return false;
    }

    buf : [size_of(Ctime_Header)]u8;
    _, err := os.read(file.handle, buf[..]);
    header := (cast(^Ctime_Header)&buf[0])^;
    if header.magic != CTIME_MAGIC_VALUE {
        return false;
    } else {
        return true;
    }
}

convert_ctime_to_otm1 :: proc(file : ^otime.File) -> bool {
    ///Create backup
    size, err := os.file_size(file.handle);
    if err != 0 {
        return false;
    }

    old_data := make([]u8, size);
    _, err = os.seek(file.handle, 0, 0);
    if err != 0 {
        return false;
    }
    _, err = os.read(file.handle, old_data);
    if err != 0 {
        return false;
    }

    str := fmt.aprintf("%s.old", file.name);
    h, e := os.open(str, os.O_CREATE | os.O_RDWR);
    free(str);
    if e != 0 {
        return false;
    }
    _, err = os.write(h, old_data);
    free(old_data);
    if err != 0 {
        return false;
    }

    data_start, ok := os.seek(file.handle, size_of(Ctime_Header), 0);
    if ok != 0 {
        return false;
    }
    ctime_entries_bytes := make([]u8, size - data_start);
    _, ok = os.read(file.handle, ctime_entries_bytes);
    if ok != 0 {
        return false;
    }
    os.close(file.handle);
    
    file.handle, err = os.open(file.name, os.O_RDWR | os.O_TRUNC);
    if err != 0 {
        return false;
    }
    otime.add_new_header_to_file(file);
    
    raw_ctime_entries := raw.Slice{
        &ctime_entries_bytes[0],
        len(ctime_entries_bytes) / size_of(Ctime_Entry),
        len(ctime_entries_bytes) / size_of(Ctime_Entry),
    };
    ctime_entries := transmute([]Ctime_Entry)raw_ctime_entries;

    entries := make([]otime.File_Entry, len(ctime_entries));
    for c, i in ctime_entries {
        entries[i].date_raw = c.date_raw;
        entries[i].time_elapsed = c.time_elapsed;

        if c.flags & u32(Ctime_Entry_Flags.NoErrors) == u32(Ctime_Entry_Flags.NoErrors) {
            entries[i].flags |= otime.File_Entry_Flags.NoError;
        }
        if c.flags & u32(Ctime_Entry_Flags.Complete) == u32(Ctime_Entry_Flags.Complete) {
            entries[i].flags |= otime.File_Entry_Flags.Complete;
        }
    }

    for e in entries {
        if otime.is_entry_flag_set(e.flags, otime.File_Entry_Flags.Complete) {
            file.header.total_ms += e.time_elapsed;
        }
        file.header.timing_count += 1;
        if !otime.write_entry_to_file(file, e) {
            return false;
        }
    }

    otime.write_header_to_file(file);
    return true;
}