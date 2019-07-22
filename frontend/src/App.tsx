import React from "react";
import { default as moment, Moment } from "moment";
import "./App.css";

enum CategoryType {
  Root = "root",
  Era = "era",
  Millennium = "millennium",
  Century = "century",
  Decade = "decade",
  Year = "year",
  Month = "month",
  Day = "day"
}

const CategoryTypeKeys = Object.keys(CategoryType);
const StringToCategoryType = new Map<string, string>(
  CategoryTypeKeys.map(a => [CategoryType[a as any], a])
);

const NextCategoryType = new Map<string, string>(
  Array.from({ length: CategoryTypeKeys.length - 1 }, (_, i) => [
    CategoryTypeKeys[i],
    CategoryTypeKeys[i + 1]
  ])
);
const PrevCategoryType = new Map<string, string>(
  Array.from({ length: CategoryTypeKeys.length - 1 }, (_, i) => [
    CategoryTypeKeys[i + 1],
    CategoryTypeKeys[i]
  ])
);

type EventData = {
  id: number;
  day?: string;
  title: string;
  img?: string;
  description?: string;
};
type CategoryData = {
  index: number[];
  type: CategoryType;
  date: Moment | null;
  subcategories: CategoryData[];
  events: EventData[];

  open: boolean;
  loading: boolean;
};

class Event extends React.Component<EventData> {
  render() {
    return (
      <li className="event">
        <span>
          <em>{this.props.day || "-"}</em>
          {" " + this.props.title}
        </span>

        <div>
          {this.props.img ? (
            <img src={this.props.img} alt={this.props.title} />
          ) : null}
          {this.props.description ? <p>{this.props.description}</p> : null}
        </div>
      </li>
    );
  }

  async loadData() {
    this.setState({ dataAvailable: true });
  }
}

type DateBounds = { min: Moment; max: Moment };
type CategoryMetadata = {
  bounds: DateBounds;
  addSubcategory: (index: number[], data: CategoryData[]) => void;
  toggle: (index: number[]) => void;
  setLoading: (index: number[], loading: boolean) => void;
};

class Category extends React.Component<CategoryData & CategoryMetadata> {
  render() {
    let title = "";
    if (this.props.date !== null) {
      const era = this.props.date.year() < 0 ? "BCE" : "CE";

      if (this.props.type === CategoryType.Era) {
        title = era;
      } else if (this.props.type === CategoryType.Millennium) {
        const year = this.props.date.year();
        title = `${Math.abs(year)} - ${Math.abs(year + 999)} ${era}`;
      } else if (this.props.type === CategoryType.Century) {
        const year = this.props.date.year();
        title = `${Math.abs(year)} - ${Math.abs(year + 99)} ${era}`;
      } else if (this.props.type === CategoryType.Decade) {
        const year = this.props.date.year();
        title = `${Math.abs(year)} - ${Math.abs(year + 9)} ${era}`;
      } else if (this.props.type === CategoryType.Year) {
        title = `${Math.abs(this.props.date.year())} ${era}`;
      } else if (this.props.type === CategoryType.Month) {
        title =
          this.props.date.format("MMMM") +
          ` ${Math.abs(this.props.date.year())} ${era}`;
      } else {
        title = "WTF";
      }
    } else {
      const prevCategoryType = CategoryType[
        PrevCategoryType.get(StringToCategoryType.get(this.props.type)!)! as any
      ] as CategoryType;

      title =
        prevCategoryType.charAt(0).toUpperCase() +
        prevCategoryType.slice(1) +
        "-wide/Undated";
    }

    if (this.props.loading) {
      title += " (loading)";
    }

    if (!this.props.open) {
      title += " ▼";
    }

    return (
      <li className={this.props.type}>
        <span className="heading" onClick={this.onClick.bind(this)}>
          {title}
        </span>

        <ul className={this.props.open ? "open" : "closed"}>
          {this.props.events.map(e => (
            <Event {...e} key={e.id + e.title} />
          ))}
          {this.props.subcategories.map(s => (
            <Category
              key={s.index.toString()}
              {...s}
              bounds={this.props.bounds}
              addSubcategory={this.props.addSubcategory}
              toggle={this.props.toggle}
              setLoading={this.props.setLoading}
            />
          ))}
        </ul>
      </li>
    );
  }

  async loadChildData() {
    const date = this.props.date;
    if (date === null) {
      return;
    }

    if (this.props.subcategories.length > 0 || this.props.events.length > 0) {
      return;
    }

    const getData = async (precision: string, date: Moment) => {
      const data = (await fetch(
        `/data/events/by-date/${date.toISOString()}/${precision}`
      ).then(a => a.json())) as { events: any[] } | { error: string };

      if ("error" in data) {
        throw new Error(data.error);
      }

      return data;
    };

    const eventData = await getData(this.props.type, date);
    let subcategories: CategoryData[] = [];

    const nextCategoryType = CategoryType[
      NextCategoryType.get(StringToCategoryType.get(this.props.type)!)! as any
    ] as CategoryType;

    const addToSubcategories = (
      date: Moment | null,
      events: EventData[] = [],
      open: boolean = false
    ) =>
      subcategories.push({
        index: this.props.index.concat(subcategories.length),
        type: nextCategoryType,
        date: date,
        subcategories: [],
        events,
        open,
        loading: false
      });

    const remapEvent = (a: any) => ({
      id: a.id,
      title: a.name ? `${a.name}, ${a.title}` : a.title,
      day:
        a.precision === "day"
          ? moment(a.date)
              .date()
              .toString()
          : undefined
    });

    const events = eventData.events.map(remapEvent);

    if (this.props.type !== "month") {
      addToSubcategories(null, events, true);
    }

    if (this.props.type === "era") {
      if (date.year() < 0) {
        const lowerBound =
          Math.floor(this.props.bounds.min.year() / 1000) * 1000;
        for (let year = lowerBound; year < 0; year += 1000) {
          addToSubcategories(date.clone().year(year));
        }
      } else {
        const upperBound =
          Math.floor(this.props.bounds.max.year() / 1000) * 1000;
        for (let year = 0; year <= upperBound; year += 1000) {
          addToSubcategories(date.clone().year(year));
        }
      }
    } else if (this.props.type === "millennium") {
      for (let i = date.year(); i < date.year() + 1000; i += 100) {
        addToSubcategories(date.clone().year(i));
      }
    } else if (this.props.type === "century") {
      for (let i = date.year(); i < date.year() + 100; i += 10) {
        addToSubcategories(date.clone().year(i));
      }
    } else if (this.props.type === "decade") {
      for (let i = date.year(); i < date.year() + 10; i++) {
        addToSubcategories(date.clone().year(i));
      }
    } else if (this.props.type === "year") {
      const tuple = <T extends any[]> (...data: T) => {
        return data;
      };

      const months = Array.from(Array(12), (_, i) => date.clone().month(i));
      const monthEvents = await Promise.all(
        months.map(date =>
          getData("month", date).then(data => tuple(date, data))
        )
      );

      for (const [date, data] of monthEvents) {
        addToSubcategories(
          date as Moment,
          data.events.map(remapEvent),
          true
        );
      }
    }

    this.props.addSubcategory(this.props.index, subcategories);
  }

  async onClick() {
    if (!this.props.loading) {
      this.props.setLoading(this.props.index, true);
      await this.loadChildData();
      this.props.setLoading(this.props.index, false);
    }
    this.props.toggle(this.props.index);
  }
}

const RootCategory = ({
  subcategories,
  bounds,
  addSubcategory,
  toggle,
  setLoading
}: CategoryData & CategoryMetadata) => (
  <ul>
    {subcategories.map(a => (
      <Category
        key={a.index.toString()}
        bounds={bounds}
        addSubcategory={addSubcategory}
        toggle={toggle}
        setLoading={setLoading}
        {...a}
      />
    ))}
  </ul>
);

class App extends React.Component {
  state = {
    bounds: undefined as DateBounds | undefined,
    root: {
      index: [0],
      type: CategoryType.Root,
      date: moment.utc(),
      subcategories: [
        {
          index: [0, 0],
          type: CategoryType.Era,
          date: moment.utc({ year: -1 }),
          subcategories: [],
          events: [],
          open: false
        },
        {
          index: [0, 1],
          type: CategoryType.Era,
          date: moment.utc({ year: 1 }),
          subcategories: [],
          events: [],
          open: false
        }
      ] as any[],
      events: [] as any[],
      open: true,
      loading: false
    }
  };

  async componentDidMount() {
    const bounds = await fetch("/data/events/bounds").then(a => a.json());
    this.setState({
      bounds: {
        min: moment.utc(bounds.min),
        max: moment.utc(bounds.max)
      }
    });
  }

  private getSubtree(index: number[]) {
    let root = { subcategories: [this.state.root] };
    let subtree = root as CategoryData;
    for (const component of index) {
      subtree = subtree.subcategories[component];
    }

    return { subtree, root: root.subcategories[0] };
  }

  addSubcategory(index: number[], data: CategoryData[]) {
    const { subtree, root } = this.getSubtree(index);
    subtree.subcategories = subtree.subcategories.concat(data);
    this.setState({ root });
  }

  toggle(index: number[]) {
    const { subtree, root } = this.getSubtree(index);
    subtree.open = !subtree.open;
    this.setState({ root });
  }

  setLoading(index: number[], loading: boolean) {
    const { subtree, root } = this.getSubtree(index);
    subtree.loading = loading;
    this.setState({ root });
  }

  render() {
    return (
      <div className="App">
        <h1>Wikiline</h1>
        {this.state.bounds !== undefined ? (
          <RootCategory
            {...this.state.root}
            bounds={this.state.bounds}
            addSubcategory={this.addSubcategory.bind(this)}
            toggle={this.toggle.bind(this)}
            setLoading={this.setLoading.bind(this)}
          />
        ) : null}
      </div>
    );
  }
}
export default App;
