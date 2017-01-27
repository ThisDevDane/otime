/*
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the
software to the public domain. We make this dedication for the benefit
of the public at large and to the detriment of our heirs and
successors. We intend this dedication to be an overt act of
relinquishment in perpetuity of all present and future rights to this
software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <http://unlicense.org>
*/

#foreign_system_library "winmm" when ODIN_OS == "windows";
#foreign_system_library "shell32" when ODIN_OS == "windows";
#import win32 "sys/windows.odin" when ODIN_OS == "windows";

timeGetTime :: proc() -> u32 #foreign #dll_import 
GetSystemTimeAsFileTime :: proc(SystemTimeAsFileTime : ^win32.FILETIME) #foreign #dll_import
FileTimeToLocalFileTime :: proc(FileTime : ^win32.FILETIME, LocalFileTime : ^win32.FILETIME) -> win32.BOOL #foreign #dll_import
FileTimeToSystemTime :: proc(FileTime : ^win32.FILETIME, SystemTime : ^SYSTEMTIME) -> win32.BOOL #foreign #dll_import
SystemTimeToFileTime  :: proc(SystemTime : ^SYSTEMTIME, FileTime : ^win32.FILETIME) -> win32.BOOL #foreign #dll_import

SYSTEMTIME :: struct #ordered {
    Year : u16;
    Month : u16;
    DayOfWeek : u16;
    Day : u16;
    Hour : u16;
    Minute : u16;
    Second : u16;
    Millisecond : u16;
}

GetCommandLineArguments :: proc() -> []string {
    to_odin_string :: proc(c: ^byte) -> string {
        s: string;
        s.data = c;
        while (c + s.count)^ != 0 {
            s.count += 1;
        }
        return s;
    }
    data := to_odin_string(win32.GetCommandLineA()) as []byte;
    string_count, string_index: int;
    new_option: bool;

    new_option = true;
    for b, i : data {
        if b == ' '    {
            data[i] = 0;
            new_option = true;
        } else {
            if new_option {
                string_count += 1;
            }
            new_option = false;
        }
    }


    strings := new_slice(string, string_count);
    new_option = true;
    for b, i : data {
        if b == 0 {
            new_option = true;
        } else {
            if new_option {
                strings[string_index] = to_odin_string(^data[i]);
                string_index += 1;
            }
            new_option = false;
        }
    }

    return strings;
}
//("Hellope!\x00" as string).data
