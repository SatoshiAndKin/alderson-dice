/** @type {import('tailwindcss').Config} */
module.exports = {
    content: {
        files: ["*.html", "./src/**/*.rs"],
    },
    theme: {
        container: {
            center: true,
            padding: '2rem',
        },
        extend: {},
    },
    plugins: [],
}