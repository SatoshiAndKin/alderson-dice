use std::process::Command;

fn main() {
    // Run the webpack build command
    let status = Command::new("node")
        .arg("esbuild.js")
        .status()
        .expect("failed to execute webpack");

    // Check if the webpack build was successful
    if !status.success() {
        panic!("esbuild failed");
    }

    println!("cargo:rerun-if-changed=src-js/");
    println!("cargo:rerun-if-changed=esbuild.js");
    println!("cargo:rerun-if-changed=tsconfig.json");
    println!("cargo:rerun-if-changed=yarn.lock");
}
