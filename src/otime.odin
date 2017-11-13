/*
 *  @Name:     otime
 *  
 *  @Author:   Mikkel Hjortshoej
 *  @Email:    hoej@northwolfprod.com
 *  @Creation: 13-11-2017 01:06:46
 *
 *  @Last By:   Mikkel Hjortshoej
 *  @Last Time: 13-11-2017 03:44:16
 *  
 *  @Description:
 *  
 */

import       "core:fmt.odin";
import       "core:os.odin";
import       "core:raw.odin";
import win32 "core:sys/windows.odin";

MAGIC_VALUE :: 0x4f544d31; //OTM1

File :: struct {
    handle : os.Handle,
    name   : string,
    header : File_Header,
}

File_Header :: struct #ordered {
    magic : u32,
    average_ms : f64,
    timing_count : u32,
}

File_Entry_Flags :: enum u32 {
    Complete = 1 << 1,
    NoError  = 1 << 1,
}

File_Entry :: struct #ordered {
    date_raw     : [2]u32, //lo, hi
    time_elapsed : u32, //In milliseconds
    flags        : File_Entry_Flags
}

read_header_and_validate :: proc(file : ^File) -> bool {
    buf : [size_of(File_Header)]u8;
    _, err := os.read(file.handle, buf[..]);
    file.header = (cast(^File_Header)&buf[0])^;
    if file.header.magic != MAGIC_VALUE {
        return false;
    } else {
        return true;
    }
}

write_new_header_to_file :: proc(file : ^File) -> bool {
    file.header = File_Header{};
    file.header.magic = MAGIC_VALUE;

    buf_raw := raw.Slice {
        cast(^File_Header)&file.header,
        size_of(file.header),
        size_of(file.header)
    };

    buf := transmute([]u8)buf_raw;
    written, err := os.write(file.handle, buf);
    if written == size_of(file.header) && err == 0 {
        return true;
    } else {
        return false;
    }
}

write_header_to_file :: proc(file : ^File) -> bool {
    _, ok := os.seek(file.handle, 0, 0);
    if ok != 0 {
        return false;
    }

    buf_raw := raw.Slice {
        cast(^File_Header)&file.header,
        size_of(file.header),
        size_of(file.header)
    };

    buf := transmute([]u8)buf_raw;
    written, err := os.write(file.handle, buf);
    if written == size_of(file.header) && err == 0 {
        return true;
    } else {
        return false;
    }
}

write_new_entry_to_file :: proc(file : ^File) -> bool {
    entry := File_Entry{};
    
    ft : win32.Filetime;
    win32.get_system_time_as_file_time(&ft);

    entry.date_raw[0] = ft.lo;
    entry.date_raw[1] = ft.hi;
    entry.time_elapsed = win32.time_get_time();

    buf_raw := raw.Slice {
        cast(^File_Entry)&entry,
        size_of(entry),
        size_of(entry)
    };
    buf := transmute([]u8)buf_raw;

    _, err := os.seek(file.handle, 0, 2);
    if err != 0 {
        return false;
    } else {
        written, err := os.write(file.handle, buf);
        if err == 0 && written == size_of(entry) {
            return true;
        } else {
            return false;
        }
    }
}

close_last_entry_in_file :: proc(file : ^File, entry : File_Entry, err_level : string) -> (already_closed : bool, write_ok : bool, time : f64) {
    if entry.flags & File_Entry_Flags.Complete == File_Entry_Flags.Complete {
        return true, false, 0;
    }

    start_time := entry.time_elapsed;
    end_time := win32.time_get_time();
    
    entry.time_elapsed = 0;
    if start_time < end_time {
        entry.time_elapsed = end_time - start_time;
    }

    if err_level == "0" {
        entry.flags |= File_Entry_Flags.NoError;
    }
    entry.flags |= File_Entry_Flags.Complete;

    _, err := os.seek(file.handle, -size_of(File_Entry), 2);
    buf_raw := raw.Slice {
        cast(^File_Entry)&entry,
        size_of(entry),
        size_of(entry)
    };
    buf := transmute([]u8)buf_raw;

    written, okw := os.write(file.handle, buf[..]);
    if written != size_of(entry) {
        return false, false, 0;
    }

    file.header.timing_count += 1;
    file.header.average_ms = (f64(entry.time_elapsed) + file.header.average_ms) / f64(file.header.timing_count);
    write_header_to_file(file);

    return false, true, f64(entry.time_elapsed);
}

read_last_entry_from_file :: proc(file : ^File) -> (File_Entry, bool) {
    _, err := os.seek(file.handle, -size_of(File_Entry), 2);
    if err != 0 {
        return File_Entry{}, false;
    }
    buf : [size_of(File_Entry)]u8;
    read : int;
    read, err = os.read(file.handle, buf[..]);
    if read == size_of(File_Entry) && err == 0 {
        entry : File_Entry = (cast(^File_Entry)&buf[0])^;
        return entry, true;
    } else {
        return File_Entry{}, false;
    }
}