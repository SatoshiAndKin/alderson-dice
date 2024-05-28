rustup target add wasm32-unknown-unknown

# Javascript builds

leptos didn't make this as simple as i'd hoped. we have a yarn project right inside our leptos project

1. You write code in `src-js`
2. `webpack build` moves the code into public-js. Don't touch these.
3. rust code with `wasm_bindgen` will do things to move it into `dist`. Don't touch these.
