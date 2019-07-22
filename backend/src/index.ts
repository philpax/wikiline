import { default as express } from 'express';
import * as pg from 'pg';

const app = express();
const db = new pg.Client({database: 'wikiline'});

app.get('/bounds', async (req, res) => {
  try {
    const result = await db.query("SELECT MIN(EventDate.date), MAX(EventDate.date) FROM EventDate");

    res.json({
      min: result.rows[0].min,
      max: result.rows[0].max,
    })
  } catch (e) {
    res.status(500).json({
      error: e.toString()
    })
  }
})

app.get('/data', async (req, res) => {
  try {
    const { date, precision } = req.query;
    let filters: { sql: string, value: any[] }[] = [];

    const jsDate = new Date(date);

    switch (precision) {
      case "era":
      {
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
          value: [],
        });
        break;
      }
      case "millennium":
      {
        const millenniumYear = Math.floor(jsDate.getFullYear() / 1000) * 1000;
        filters.push({
          sql: "date_part('year', EventDate.date) = $1",
          value: [millenniumYear]
        });
        filters.push({
          sql: "EventDate.precision = 'millennium'",
          value: [],
        });
        break;
      }
      case "century":
      {
        const centuryYear = Math.floor(jsDate.getFullYear() / 100) * 100;
        filters.push({
          sql: "date_part('year', EventDate.date) = $1",
          value: [centuryYear]
        });
        filters.push({
          sql: "EventDate.precision = 'century'",
          value: [],
        });
        break;
      }
      case "decade":
      {
        const decadeYear = Math.floor(jsDate.getFullYear() / 10) * 10;
        filters.push({
          sql: "date_part('year', EventDate.date) = $1",
          value: [decadeYear]
        });
        filters.push({
          sql: "EventDate.precision = 'decade'",
          value: [],
        });
        break;
      }
      case "year":
      {
        filters.push({
          sql: "date_part('year', EventDate.date) = $1",
          value: [jsDate.getFullYear()]
        });
        filters.push({
          sql: "EventDate.precision = 'year'",
          value: [],
        });
        break;
      }
      case "month":
      {
        const startDate = new Date(jsDate.getFullYear(), jsDate.getMonth(), 1);
        const endDate = new Date(jsDate.getFullYear(), jsDate.getMonth()+1, 0);
        filters.push({
          sql: "EventDate.date BETWEEN $1 AND $2",
          value: [startDate, endDate]
        });
        filters.push({
          sql: "(EventDate.precision = 'month' OR EventDate.precision = 'day')",
          value: [],
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

    query += "\nORDER BY EventDate.precision, EventDate.date"
    const values = ([] as any[]).concat(...filters.map(a => a.value));
    // console.log(query, values);
    const result = await db.query(query, values);

    res.json(result.rows || []);
  } catch (e) {
    res.status(500).json({
      error: e.toString()
    })
  }
});

async function main() {
  await db.connect();

  app.listen(3001, () => console.log("listening"));
}

main();