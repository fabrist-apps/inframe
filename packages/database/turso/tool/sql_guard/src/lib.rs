use std::{
    alloc::{self, Layout},
    slice,
};

use turso_parser::ast::{Cmd, Expr, Literal, Stmt, Variable};
use turso_parser::parser::Parser;

const ABI_VERSION: u32 = 1;
const VALID: u32 = 0;
const EMPTY: u32 = 1;
const TRAILING_STATEMENT: u32 = 2;
const INVALID_TRAILING_SQL: u32 = 3;
const INVALID_UTF8: u32 = 4;

const ORDINARY_STATEMENT: u32 = 0;
const ATTACH_STATEMENT: u32 = 1;
const DETACH_STATEMENT: u32 = 2;

const NO_ARGUMENT: u32 = 0;
const DIRECT_ARGUMENT: u32 = 1;
const BOUND_ARGUMENT: u32 = 2;
const UNSUPPORTED_ARGUMENT: u32 = 3;

const INSPECTION_HEADER_LENGTH: usize = 48;

#[no_mangle]
pub extern "C" fn turso_sql_guard_alloc(length: usize) -> *mut u8 {
    if length == 0 {
        return std::ptr::NonNull::<u8>::dangling().as_ptr();
    }
    let layout = Layout::array::<u8>(length).expect("valid SQL guard allocation");
    let pointer = unsafe { alloc::alloc(layout) };
    if pointer.is_null() {
        alloc::handle_alloc_error(layout);
    }
    pointer
}

#[no_mangle]
pub unsafe extern "C" fn turso_sql_guard_dealloc(pointer: *mut u8, length: usize) {
    if length == 0 {
        return;
    }
    let layout = Layout::array::<u8>(length).expect("valid SQL guard allocation");
    alloc::dealloc(pointer, layout);
}

/// Parses one statement and returns a versioned metadata block owned by the caller.
///
/// The block starts with its total byte length, followed by the ABI version,
/// validation status, statement kind, and two argument descriptors. ATTACH uses
/// both descriptors; DETACH uses the first. Each descriptor contains its form,
/// one-based binding index, payload offset, and payload byte length.
#[no_mangle]
pub unsafe extern "C" fn turso_sql_guard_inspect(pointer: *const u8, length: usize) -> *mut u8 {
    let bytes = slice::from_raw_parts(pointer, length);
    allocate_inspection(Inspection::from_bytes(bytes).encode())
}

/// Checks that `sql` contains exactly one statement using the pinned Turso parser.
///
/// Syntax errors are left to the database so callers receive the engine's full
/// diagnostic. This adapter only distinguishes empty input and a parsed tail.
#[no_mangle]
pub unsafe extern "C" fn turso_sql_guard_validate(pointer: *const u8, length: usize) -> u32 {
    let bytes = slice::from_raw_parts(pointer, length);
    Inspection::from_bytes(bytes).status
}

#[derive(Debug, PartialEq, Eq)]
struct Inspection {
    status: u32,
    kind: u32,
    first: Argument,
    second: Argument,
}

impl Inspection {
    fn from_bytes(bytes: &[u8]) -> Self {
        if std::str::from_utf8(bytes).is_err() {
            return Self::status(INVALID_UTF8);
        }

        let mut parser = Parser::new(bytes);
        let command = match parser.next() {
            None => return Self::status(EMPTY),
            Some(Err(_)) => return Self::status(VALID),
            Some(Ok(command)) => command,
        };
        match parser.next() {
            Some(Ok(_)) => return Self::status(TRAILING_STATEMENT),
            Some(Err(_)) => return Self::status(INVALID_TRAILING_SQL),
            None => {}
        }

        match command {
            Cmd::Stmt(Stmt::Attach {
                expr,
                db_name,
                key: _,
            }) => Self {
                status: VALID,
                kind: ATTACH_STATEMENT,
                first: Argument::from_expr(&expr),
                second: Argument::from_expr(&db_name),
            },
            Cmd::Stmt(Stmt::Detach { name }) => Self {
                status: VALID,
                kind: DETACH_STATEMENT,
                first: Argument::from_expr(&name),
                second: Argument::none(),
            },
            Cmd::Explain(_) | Cmd::ExplainQueryPlan { .. } | Cmd::Stmt(_) => Self::status(VALID),
        }
    }

    fn status(status: u32) -> Self {
        Self {
            status,
            kind: ORDINARY_STATEMENT,
            first: Argument::none(),
            second: Argument::none(),
        }
    }

    fn encode(self) -> Vec<u8> {
        let mut bytes = vec![0; INSPECTION_HEADER_LENGTH];
        write_u32(&mut bytes, 4, ABI_VERSION);
        write_u32(&mut bytes, 8, self.status);
        write_u32(&mut bytes, 12, self.kind);
        encode_argument(&mut bytes, 16, self.first);
        encode_argument(&mut bytes, 32, self.second);
        let length = u32::try_from(bytes.len()).expect("SQL inspection fits in WASM memory");
        write_u32(&mut bytes, 0, length);
        bytes
    }
}

#[derive(Debug, PartialEq, Eq)]
struct Argument {
    form: u32,
    binding_index: u32,
    payload: String,
}

impl Argument {
    fn none() -> Self {
        Self {
            form: NO_ARGUMENT,
            binding_index: 0,
            payload: String::new(),
        }
    }

    fn from_expr(expression: &Expr) -> Self {
        match expression {
            Expr::Literal(Literal::String(value)) => Self::direct(decode_string_literal(value)),
            Expr::Qualified(_, _) => Self::direct(expression.to_string()),
            Expr::Id(name) => Self::direct(name.as_str().to_ascii_lowercase()),
            Expr::Variable(variable) => Self::bound(variable),
            _ => Self {
                form: UNSUPPORTED_ARGUMENT,
                binding_index: 0,
                payload: String::new(),
            },
        }
    }

    fn direct(payload: String) -> Self {
        Self {
            form: DIRECT_ARGUMENT,
            binding_index: 0,
            payload,
        }
    }

    fn bound(variable: &Variable) -> Self {
        let payload = match &variable.name {
            Some(name) => name.to_string(),
            None if variable.numbered => format!("?{}", variable.index),
            None => String::new(),
        };
        Self {
            form: BOUND_ARGUMENT,
            binding_index: variable.index.get(),
            payload,
        }
    }
}

fn decode_string_literal(value: &str) -> String {
    value[1..value.len() - 1].replace("''", "'")
}

fn encode_argument(bytes: &mut Vec<u8>, offset: usize, argument: Argument) {
    write_u32(bytes, offset, argument.form);
    write_u32(bytes, offset + 4, argument.binding_index);
    if argument.payload.is_empty() {
        return;
    }
    let payload_offset = u32::try_from(bytes.len()).expect("SQL inspection fits in WASM memory");
    let payload_length =
        u32::try_from(argument.payload.len()).expect("SQL inspection fits in WASM memory");
    write_u32(bytes, offset + 8, payload_offset);
    write_u32(bytes, offset + 12, payload_length);
    bytes.extend_from_slice(argument.payload.as_bytes());
}

fn write_u32(bytes: &mut [u8], offset: usize, value: u32) {
    bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
}

fn allocate_inspection(bytes: Vec<u8>) -> *mut u8 {
    let layout = Layout::array::<u8>(bytes.len()).expect("valid SQL inspection allocation");
    let pointer = unsafe { alloc::alloc(layout) };
    if pointer.is_null() {
        alloc::handle_alloc_error(layout);
    }
    unsafe { pointer.copy_from_nonoverlapping(bytes.as_ptr(), bytes.len()) };
    pointer
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inspects_direct_attach_and_detach_arguments() {
        assert_eq!(
            inspect("ATTACH DATABASE 'other''s.db' AS \"Aux\""),
            Inspection {
                status: VALID,
                kind: ATTACH_STATEMENT,
                first: Argument::direct("other's.db".to_string()),
                second: Argument::direct("aux".to_string()),
            }
        );
        assert_eq!(
            inspect("DETACH DATABASE other.schema"),
            Inspection {
                status: VALID,
                kind: DETACH_STATEMENT,
                first: Argument::direct("other.schema".to_string()),
                second: Argument::none(),
            }
        );
    }

    #[test]
    fn preserves_parser_binding_slots_and_names() {
        let inspection = inspect("ATTACH DATABASE ?2 AS :schema KEY $keys::value");
        assert_eq!(inspection.kind, ATTACH_STATEMENT);
        assert_eq!(
            inspection.first,
            Argument {
                form: BOUND_ARGUMENT,
                binding_index: 2,
                payload: "?2".to_string(),
            }
        );
        assert_eq!(
            inspection.second,
            Argument {
                form: BOUND_ARGUMENT,
                binding_index: 3,
                payload: ":schema".to_string(),
            }
        );

        let bare = inspect("ATTACH DATABASE ? AS @schema KEY ?5");
        assert_eq!(
            bare.first,
            Argument {
                form: BOUND_ARGUMENT,
                binding_index: 1,
                payload: String::new(),
            }
        );
        assert_eq!(
            bare.second,
            Argument {
                form: BOUND_ARGUMENT,
                binding_index: 2,
                payload: "@schema".to_string(),
            }
        );

        let repeated = inspect("ATTACH DATABASE :file AS $schema KEY :file");
        assert_eq!(repeated.first.binding_index, 1);
        assert_eq!(repeated.first.payload, ":file");
        assert_eq!(repeated.second.binding_index, 2);
        assert_eq!(repeated.second.payload, "$schema");
    }

    #[test]
    fn inspects_bound_detach_and_direct_edge_cases() {
        let detached = inspect("DETACH DATABASE ?1");
        assert_eq!(detached.kind, DETACH_STATEMENT);
        assert_eq!(
            detached.first,
            Argument {
                form: BOUND_ARGUMENT,
                binding_index: 1,
                payload: "?1".to_string(),
            }
        );

        let direct = inspect("ATTACH DATABASE '' AS [Mixed Name]");
        assert_eq!(direct.first, Argument::direct(String::new()));
        assert_eq!(direct.second, Argument::direct("mixed name".to_string()));
    }

    #[test]
    fn rejects_computed_arguments_and_ignores_explain() {
        let computed = inspect("ATTACH DATABASE 'other' || '.db' AS auxiliary");
        assert_eq!(computed.first.form, UNSUPPORTED_ARGUMENT);
        assert_eq!(computed.second, Argument::direct("auxiliary".to_string()));

        let explained = inspect("EXPLAIN ATTACH DATABASE 'other.db' AS auxiliary");
        assert_eq!(explained.kind, ORDINARY_STATEMENT);
    }

    #[test]
    fn retains_validation_results_and_encodes_unicode_payloads() {
        assert_eq!(inspect("").status, EMPTY);
        assert_eq!(inspect("SELECT 1; SELECT 2").status, TRAILING_STATEMENT);
        assert_eq!(
            inspect("SELECT 1; broken syntax").status,
            INVALID_TRAILING_SQL
        );

        let encoded = inspect("ATTACH DATABASE '数据.db' AS auxiliary").encode();
        assert_eq!(read_u32(&encoded, 0) as usize, encoded.len());
        assert_eq!(read_u32(&encoded, 4), ABI_VERSION);
        assert_eq!(read_u32(&encoded, 8), VALID);
        assert_eq!(read_u32(&encoded, 12), ATTACH_STATEMENT);
        let payload_offset = read_u32(&encoded, 24) as usize;
        let payload_length = read_u32(&encoded, 28) as usize;
        assert_eq!(
            std::str::from_utf8(&encoded[payload_offset..payload_offset + payload_length]).unwrap(),
            "数据.db"
        );

        assert_eq!(Inspection::from_bytes(&[0xff]).status, INVALID_UTF8);
    }

    fn inspect(sql: &str) -> Inspection {
        Inspection::from_bytes(sql.as_bytes())
    }

    fn read_u32(bytes: &[u8], offset: usize) -> u32 {
        u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap())
    }
}
