extern crate getopts;
extern crate syntect;

use std::env;
use std::fmt::Write;
use std::io::BufRead;
use std::path::Path;

use getopts::Options;

use syntect::easy::HighlightFile;
use syntect::highlighting::{FontStyle, Style, ThemeSet};
use syntect::parsing::SyntaxSet;
//use syntect::util::as_24_bit_terminal_escaped;

// https://stackoverflow.com/a/66401342/309233
fn strip_trailing_newline(input: &str) -> &str {
    input
        .strip_suffix("\r\n")
        .or(input.strip_suffix("\n"))
        .unwrap_or(input)
}

fn as_enscript_escaped(v: &[(Style, &str)], bg: bool) -> String {
    let mut s: String = String::new();

    for &(ref style, text) in v.iter() {
        let has_newline = text.ends_with('\n');
        let text_no_newline = strip_trailing_newline(text);

        if bg {
            write!(
                s,
                "\\bg{{{};{};{};}}",
                style.background.r, style.background.g, style.background.b
            )
            .unwrap();
        }

        // TODO: figure out how fonts actually work in Enscript, and get our
        // font info from that knowledge.

        // TODO: handle combinations (PostScript uses separate fonts for Oblique, Bold, and BoldOblique)
        if style.font_style.contains(FontStyle::ITALIC) {
            // italic
            write!(s, "\0font{{Courier-Oblique@6}}").unwrap();
        } else if style.font_style.contains(FontStyle::BOLD) {
            // bold
            write!(s, "\0font{{Courier-Bold@6}}").unwrap();
        }

        // TODO: UNDERLINE

        write!(
            s,
            "\0color{{{} {} {}}}{}\0font{{default}}\0color{{default}}",
            ((style.foreground.r as f32) / 255.),
            ((style.foreground.g as f32) / 255.),
            ((style.foreground.b as f32) / 255.),
            text_no_newline
        )
        .unwrap();

        if has_newline {
            write!(s, "\n").unwrap();
        }
    }

    s
}

fn main() {
    let args: Vec<String> = env::args().collect();
    // let program = args[0].clone();
    let mut opts = Options::new();

    // kinda stolen from `syncat` while I'm learning Rust
    opts.optflag("l", "list-file-types", "Lists supported file types");
    //opts.optflag("L", "list-embedded-themes", "Lists themes present in the executable");
    opts.optopt("t", "theme-file", "THEME_FILE", "Theme file to use. May be a path, or an embedded theme. Embedded themes will take precedence. Default: base16-ocean.dark");
    opts.optopt("s", "extra-syntaxes", "SYNTAX_FOLDER", "Additional folder to search for .sublime-syntax files.");
    opts.optflag("e", "no-default-syntaxes", "Doesn't load default syntaxes. Intended for use with --extra-syntaxes.");
    //opts.optflag("n", "no-newlines", "Use the no-newlines versions of syntaxes and dumps.");
    //opts.optflag("c", "cache-theme", "Cache the parsed theme file.");

    let matches = match opts.parse(&args[1..]) {
        Ok(m) => m,
        Err(f) => {
            panic!("{}", f.to_string())
        }
    };

    let mut ss = if matches.opt_present("no-default-syntaxes") {
        SyntaxSet::new()
    } else {
        SyntaxSet::load_defaults_newlines()
    };

    if let Some(folder) = matches.opt_str("extra-syntaxes") {
        let mut builder = ss.into_builder();
        builder.add_from_folder(folder, true).unwrap();
        ss = builder.build();
    }

    if matches.opt_present("list-file-types") {
        println!("Supported file types:");

        for sd in ss.syntaxes() {
            println!(" - {} (.{})", sd.name, sd.file_extensions.join(", ."));
        }
    } else if matches.free.is_empty() {
        let brief = format!("USAGE: {} [options] FILES", args[0]);
        println!("{}", opts.usage(&brief));
    } else {
        let theme_file: String = matches
            .opt_str("theme-file")
            .unwrap_or_else(|| "testdata/themes/base16-ocean.tmTheme".to_string());
        let theme_path = Path::new(&theme_file);
        let theme = ThemeSet::get_theme(theme_path).unwrap();

        for src in &matches.free[..] {
            //println!("source: {}", src);

            let mut h = HighlightFile::new(src, &ss, &theme).unwrap();

            let mut line = String::new();
            while h.reader.read_line(&mut line).unwrap() > 0 {
                {
                    let regions: Vec<(Style, &str)> = h.highlight_lines.highlight(&line, &ss);
                    print!("{}", as_enscript_escaped(&regions[..], false));
                }
                line.clear();
            }

            // Clear the formatting
            //println!("\x1b[0m");
        }
    }

    // base16-atelier-seaside-light
    // base16-atelier-sulphurpool-light
    // base16-classic-light
    // base16-cupertino
    // base16-default-light
    // base16-github
    // base16-google-light
    // base16-harmonic-light
    // base16-ia-light
    // base16-material-lighter
    // base16-mexico-light
    // base16-one-light
    // base16-papercolor-light <<-- need to fix string color though - ugly dark green background
    // base16-summerfruit-light
    // base16-tomorrow
    // base16-unikitty-light
}
