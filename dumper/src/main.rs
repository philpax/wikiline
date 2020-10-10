#![feature(integer_atomics)]

use std::fs::File;
use std::io::{BufRead, BufReader, BufWriter, Read, Write};
use std::iter::Iterator;
use std::str;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Instant;

use bzip2::bufread::BzDecoder;

use rayon::prelude::*;

use roxmltree;

use serde::{Deserialize, Serialize};

fn get_stream_offsets(path: &str) -> std::io::Result<Vec<usize>> {
    let new_path = str::replace(path, "multistream.xml.bz2", "multistream-index.txt.bz2");
    let file = File::open(new_path)?;

    let file_reader = BufReader::new(file);

    let file_reader = BzDecoder::new(file_reader);
    let file_reader = BufReader::new(file_reader);

    let mut result = vec![];
    for line in file_reader.lines() {
        let number = line?
            .split(":")
            .next()
            .ok_or(std::io::Error::new(
                std::io::ErrorKind::Other,
                "failed to get next line",
            ))?
            .parse::<usize>()
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;

        if result.len() == 0 || *(result.last().unwrap()) != number {
            result.push(number);
        }
    }

    Ok(result)
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Article {
    title: String,
    text: String,
}

fn get_text_of_child_tag(tag: &roxmltree::Node, tag_name: &str) -> Option<String> {
    Some(
        tag.children()
            .find(|n| n.tag_name().name() == tag_name)?
            .text()?
            .to_string(),
    )
}

macro_rules! skip_fail {
    ($res:expr) => {
        match $res {
            Some(val) => val,
            None => continue,
        }
    };
}

fn get_articles_from_chunk(
    data: &[u8],
    infoboxes: &[String],
    blacklisted_prefixes: &[String],
    counter: &AtomicU64,
) -> std::io::Result<Vec<Article>> {
    let reader = BzDecoder::new(data);
    let mut reader = BufReader::new(reader);

    let mut result = vec![];

    let mut data = String::new();
    reader.read_to_string(&mut data)?;

    let rooted_xml = format!("<root>{}</root>", &data);

    let doc = roxmltree::Document::parse(&rooted_xml).unwrap();

    for t in doc.descendants().filter(|t| t.tag_name().name() == "page") {
        let title = skip_fail!(get_text_of_child_tag(&t, "title"));
        if blacklisted_prefixes.iter().any(|p| title.starts_with(p)) {
            continue;
        }

        let revision = skip_fail!(t.children().find(|n| n.tag_name().name() == "revision"));
        let text = skip_fail!(get_text_of_child_tag(&revision, "text"));

        let lowercase_text: String = text.to_lowercase();
        let contained: bool = infoboxes.iter().any(|i| lowercase_text.contains(i));
        if contained {
            result.push(Article { title, text });
        }
    }
    let counter_value = counter.fetch_add(1, Ordering::SeqCst);
    if (counter_value % 1000) == 0 {
        println!("dump: {} offsets completed", counter_value);
    }

    Ok(result)
}

fn duration_secs(duration: &std::time::Duration) -> f64 {
    duration.as_secs() as f64 + duration.subsec_nanos() as f64 * 1e-9
}

fn main() -> std::io::Result<()> {
    const PATH: &'static str = "../data/enwiki-20200901-pages-articles-multistream.xml.bz2";
    const INDEX_PATH: &'static str = "../data/index.txt";
    const SUPPORTED_INFOBOXES_PATH: &'static str = "../common/supported-infoboxes.txt";
    const BLACKLISTED_PREFIXES_PATH: &'static str = "../common/blacklisted-prefixes.txt";
    const OUTPUT_PATH: &'static str = "../data/raw-events.ndjson";

    // Start timing.
    let total_now = Instant::now();

    // Retrieve supported infoboxes.
    let infoboxes_file = File::open(SUPPORTED_INFOBOXES_PATH)?;
    let infoboxes: Vec<String> = BufReader::new(infoboxes_file)
        .lines()
        .map(|l| "{{infobox ".to_owned() + &l.unwrap())
        .collect();

    // Retrieve blacklisted prefixes.
    let blacklisted_prefixes_file = File::open(BLACKLISTED_PREFIXES_PATH)?;
    let blacklisted_prefixes: Vec<String> = BufReader::new(blacklisted_prefixes_file)
        .lines()
        .map(|l| l.unwrap().to_owned())
        .collect();

    // Create or retrieve the byte offsets.
    let offsets: Vec<usize>;
    if std::fs::metadata(INDEX_PATH).is_ok() {
        let index_file = File::open(INDEX_PATH)?;
        let file_reader = BufReader::new(index_file);
        offsets = file_reader
            .lines()
            .map(|l| l.unwrap().parse::<usize>().unwrap())
            .collect();
    } else {
        let index_file = File::create(INDEX_PATH)?;
        let mut index_file = BufWriter::new(index_file);
        offsets = get_stream_offsets(PATH)?;
        for location in &offsets {
            writeln!(&mut index_file, "{}", location)?;
        }
    }

    // Load bz2 into memory.
    let mut file = File::open(PATH)?;
    let len = file.metadata()?.len();
    println!("dump: file length {}", len);

    // Add one extra element of capacity to prevent Vec growth.
    let now = Instant::now();
    let mut data: Vec<u8> = Vec::with_capacity((len + 1) as usize);
    file.read_to_end(&mut data)?;
    println!(
        "dump: loaded bz2 into memory, {}s",
        duration_secs(&now.elapsed())
    );

    // Extract articles.
    println!("dump: iterating over {} offsets", offsets.len());
    let counter = AtomicU64::new(0);
    let now = Instant::now();
    let articles: Vec<Article> = offsets
        .par_windows(2)
        .flat_map(|os| {
            get_articles_from_chunk(
                &data[os[0]..os[1]],
                &infoboxes,
                &blacklisted_prefixes,
                &counter,
            )
            .unwrap()
        })
        .collect();
    println!("dump: iterated, {}s", duration_secs(&now.elapsed()));

    // Write articles to JSON.
    let now = Instant::now();
    println!("dump: writing to json");

    let output_file = File::create(OUTPUT_PATH)?;
    let mut output_file = BufWriter::new(output_file);
    for article in articles {
        let json = serde_json::to_string(&article)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
        output_file.write_all(json.as_bytes())?;
        output_file.write_all(b"\n")?;
    }
    println!("dump: wrote to json, {}s", duration_secs(&now.elapsed()));

    println!("dump: end, {}s", duration_secs(&total_now.elapsed()));
    Ok(())
}
