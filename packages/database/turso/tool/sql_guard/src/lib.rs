use std::{mem, slice};

use turso_parser::parser::Parser;

const VALID: u32 = 0;
const EMPTY: u32 = 1;
const TRAILING_STATEMENT: u32 = 2;
const INVALID_TRAILING_SQL: u32 = 3;
const INVALID_UTF8: u32 = 4;

#[no_mangle]
pub extern "C" fn turso_sql_guard_alloc(length: usize) -> *mut u8 {
    let mut bytes = Vec::<u8>::with_capacity(length);
    let pointer = bytes.as_mut_ptr();
    mem::forget(bytes);
    pointer
}

#[no_mangle]
pub unsafe extern "C" fn turso_sql_guard_dealloc(pointer: *mut u8, length: usize) {
    drop(Vec::from_raw_parts(pointer, 0, length));
}

/// Checks that `sql` contains exactly one statement using the pinned Turso parser.
///
/// Syntax errors are left to the database so callers receive the engine's full
/// diagnostic. This adapter only distinguishes empty input and a parsed tail.
#[no_mangle]
pub unsafe extern "C" fn turso_sql_guard_validate(pointer: *const u8, length: usize) -> u32 {
    let bytes = slice::from_raw_parts(pointer, length);
    if std::str::from_utf8(bytes).is_err() {
        return INVALID_UTF8;
    }

    let mut parser = Parser::new(bytes);
    match parser.next() {
        None => EMPTY,
        Some(Err(_)) => VALID,
        Some(Ok(_)) => match parser.next() {
            None => VALID,
            Some(Ok(_)) => TRAILING_STATEMENT,
            Some(Err(_)) => INVALID_TRAILING_SQL,
        },
    }
}
