import { default as express } from "express";
import * as pg from "pg";
import { JSDOM } from "jsdom";
import * as url from "url";

const parsoid = require("parsoid");
const unescape = require("unescape");

const app = express();
const db = new pg.Client({ database: "wikiline" });

app.get("/data/events/bounds", async (_, res) => {
  try {
    const result = await db.query(
      "SELECT MIN(EventDate.date), MAX(EventDate.date) FROM EventDate"
    );

    res.json({
      min: result.rows[0].min,
      max: result.rows[0].max
    });
  } catch (e) {
    res.status(500).json({
      error: e.toString()
    });
  }
});

app.get("/data/events/by-id/:id", async (req, res) => {
  try {
    const { id } = req.params;

    let query = `
      SELECT
        Event.id, Event.image, EventDate.name, EventDate.date, EventDate.precision, Page.title, Page.description
      FROM
        Event
      INNER JOIN
        Page ON Event.page_id = Page.id
      INNER JOIN
        EventDate ON EventDate.event_id = Event.id
      WHERE
        Event.id = $1
    `;
    const result = await db.query(query, [id]);

    const event = result.rows[0];
    event.description = (await parsoid.parse({
      parsoidOptions: {
        loadWMF: true,
        mwApis: [{ uri: "https://en.wikipedia.org/w/api.php" }],

        fetchConfig: false,
        fetchTemplates: false,
        fetchImageInfo: false,
        usePHPPreProcessor: false,
        expandExtensions: false
      },
      envOptions: {
        domain: "en.wikipedia.org",
        logLevels: ["fatal", "error"]
      },
      input: result.rows[0].description,
      mode: "wt2html"
    })).html;

    const dom = new JSDOM(event.description);

    const doc = dom.window.document;

    const elements = doc.querySelectorAll("*");
    elements.forEach(element => {
      element.removeAttribute("data-parsoid");
      element.removeAttribute("data-mwSectionId");
      element.removeAttribute("data-mw");
      element.removeAttribute("rel");
      element.removeAttribute("typeof");
    });

    const removeSelectors = [".mw-references-wrap", "sup"];
    removeSelectors.forEach(s =>
      doc.querySelectorAll(s).forEach(a => a.parentElement!.removeChild(a))
    );

    const baseUrl = doc.querySelector("base")!.getAttribute("href")!;
    doc
      .querySelectorAll("a")!
      .forEach(a =>
        a.setAttribute("href", url.resolve(baseUrl, a.getAttribute("href")!))
      );

    event.description = unescape(doc.querySelector("section")!.innerHTML);
    if (event.image) {
      let image = event.image as string;
      const matches = image.match(/\[\[File:(?<filename>.*?)\|.*?\]\]/i);
      if (matches && matches.groups && matches.groups.filename) {
        image = matches.groups.filename;
      }
      event.image = "https://en.wikipedia.org/wiki/Special:FilePath/" + image;
    }
    dom.window.close();

    res.json(event);
  } catch (e) {
    res.status(500).json({
      error: e.toString()
    });
  }
});

app.get("/data/events/by-date/:date/:precision", async (req, res) => {
  try {
    const { date, precision } = req.params;
    let filters: { sql: string; value: any[] }[] = [];

    const jsDate = new Date(date);

    switch (precision) {
      case "era": {
        if (jsDate.getFullYear() < 0) {
          filters.push({
            sql: "EventDate.date < '0001-01-01'",
            value: []
          });
        } else {
          filters.push({
            sql: "EventDate.date >= '0001-01-01'",
            value: []
          });
        }

        filters.push({
          sql: "EventDate.precision = 'era'",
          value: []
        });
        break;
      }
      case "millennium": {
        const millenniumYear = Math.floor(jsDate.getFullYear() / 1000) * 1000;
        filters.push({
          sql: "date_part('year', EventDate.date) = $1",
          value: [millenniumYear]
        });
        filters.push({
          sql: "EventDate.precision = 'millennium'",
          value: []
        });
        break;
      }
      case "century": {
        const centuryYear = Math.floor(jsDate.getFullYear() / 100) * 100;
        filters.push({
          sql: "date_part('year', EventDate.date) = $1",
          value: [centuryYear]
        });
        filters.push({
          sql: "EventDate.precision = 'century'",
          value: []
        });
        break;
      }
      case "decade": {
        const decadeYear = Math.floor(jsDate.getFullYear() / 10) * 10;
        filters.push({
          sql: "date_part('year', EventDate.date) = $1",
          value: [decadeYear]
        });
        filters.push({
          sql: "EventDate.precision = 'decade'",
          value: []
        });
        break;
      }
      case "year": {
        filters.push({
          sql: "date_part('year', EventDate.date) = $1",
          value: [jsDate.getFullYear()]
        });
        filters.push({
          sql: "EventDate.precision = 'year'",
          value: []
        });
        break;
      }
      case "month": {
        const startDate = new Date(jsDate.getFullYear(), jsDate.getMonth(), 1);
        const endDate = new Date(
          jsDate.getFullYear(),
          jsDate.getMonth() + 1,
          0
        );
        filters.push({
          sql: "EventDate.date BETWEEN $1 AND $2",
          value: [startDate, endDate]
        });
        filters.push({
          sql: "(EventDate.precision = 'month' OR EventDate.precision = 'day')",
          value: []
        });
        break;
      }
      default:
        throw new Error("unsupported precision " + precision);
    }

    let query = `
      SELECT
        Event.id, EventDate.name, EventDate.date, EventDate.precision, Page.title
      FROM
        Event
      INNER JOIN
        Page ON Event.page_id = Page.id
      INNER JOIN
        EventDate ON EventDate.event_id = Event.id
    `;

    if (filters.length > 0) {
      query += "WHERE " + filters.map(a => a.sql).join(" AND ");
    }

    query += "\nORDER BY EventDate.precision, EventDate.date";
    const values = ([] as any[]).concat(...filters.map(a => a.value));
    // console.log(query, values);
    const result = await db.query(query, values);
    const events = result.rows || [];

    res.json({
      events
    });
  } catch (e) {
    res.status(500).json({
      error: e.toString()
    });
  }
});

async function main() {
  await db.connect();

  app.listen(3001, () => console.log("listening"));
}

main();
