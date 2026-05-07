const fs = require("fs");

function block(p) {
    if (!p) return;
    const s = p.toString();
    
    // Strict Path Blocking:
    // If the application attempts to read sensitive files, instantly terminate the operation.
    // We do not rely on spoofable CallSite stack traces (Error.prepareStackTrace).
    if (s.includes("auth.json") || s.includes("gh_") || s.includes(".secrets") || s.includes(".env")) {
        throw new Error("[SYSTEM BLOCK] Access to core credential files is hardware-locked and isolated from the agent runtime.");
    }
}

// Intercept all major filesystem operations to prevent Node.js native exfiltration
const hooks = [
    "readFile", "readFileSync", "createReadStream", 
    "writeFile", "writeFileSync", "createWriteStream", "appendFile", "appendFileSync",
    "open", "openSync", 
    "unlink", "unlinkSync", "rm", "rmSync", "rmdir", "rmdirSync",
    "readdir", "readdirSync"
];

hooks.forEach(fn => {
    // Hook standard fs callbacks/sync methods
    if (fs[fn]) {
        const orig = fs[fn];
        fs[fn] = function(...args) { 
            const p = args[0] ? args[0].toString() : "";
            block(p); 
            return orig.apply(this, args); 
        };
    }
    // Hook fs.promises methods
    if (fs.promises && fs.promises[fn]) {
        const origP = fs.promises[fn];
        fs.promises[fn] = async function(...args) { 
            const p = args[0] ? args[0].toString() : "";
            block(p); 
            return origP.apply(this, args); 
        };
    }
});