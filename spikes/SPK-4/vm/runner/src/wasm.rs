//! The JavaScript surface: `new Runner(executableJson)`, then `runner.run("0x7,0x0,...")`, which
//! returns the outcome as JSON (`outcome_json`).

use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct Runner {
    exe: crate::Executable,
}

#[wasm_bindgen]
impl Runner {
    #[wasm_bindgen(constructor)]
    pub fn new(executable_json: &str) -> Result<Runner, JsError> {
        Ok(Runner { exe: crate::Executable::load(executable_json).map_err(|e| JsError::new(&e))? })
    }

    /// Runs `main` with its serialized arguments (felts in hex or decimal, comma-separated).
    pub fn run(&self, args: &str) -> Result<String, JsError> {
        let args = crate::parse_felts(args).map_err(|e| JsError::new(&e))?;
        let o = self.exe.run(&args).map_err(|e| JsError::new(&e))?;
        Ok(crate::outcome_json(&o))
    }

    #[wasm_bindgen(js_name = bytecodeLen)]
    pub fn bytecode_len(&self) -> usize {
        self.exe.bytecode_len
    }
}
