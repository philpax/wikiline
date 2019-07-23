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

  name?: string;
  title: string;

  image?: string;
  description?: string;

  open: boolean;
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

type EventProperties = {
  updateData: (newData: EventData) => void;
  toggle: () => void;
};

type DateBounds = { min: Moment; max: Moment };
type CategoryProperties = {
  bounds: DateBounds;

  addSubcategory: (index: number[], data: CategoryData[]) => void;
  toggle: (index: number[]) => void;
  setLoading: (index: number[], loading: boolean) => void;

  updateEventData: (
    categoryIndex: number[],
    eventIndex: number,
    data: EventData
  ) => void;
  toggleEvent: (categoryIndex: number[], eventIndex: number) => void;
};

function remapEvent(a: any): EventData {
  return {
    id: a.id,
    day:
      a.precision === "day"
        ? moment(a.date)
            .date()
            .toString()
        : undefined,
    name: a.name,
    title: a.title,
    image: a.image,
    description: a.description,
    open: false
  };
}

class Event extends React.Component<EventData & EventProperties> {
  render() {
    return (
      <li className="event">
        <span onClick={this.onClick.bind(this)}>
          <em>{this.props.day || "-"}</em>
          {" "}
          {this.props.name ? (<span><b>{this.props.name}</b>{", "}</span>) : ""}
          {this.props.title}
        </span>

        <div className={this.props.open ? "open" : "closed"}>
          {this.props.description ? (
            <div
              className="event-content"
              dangerouslySetInnerHTML={{ __html: this.props.description }}
            />
          ) : null}
          {this.props.image ? (
            <img
              className="event-image"
              src={this.props.image}
              alt={this.props.title}
            />
          ) : null}
        </div>
      </li>
    );
  }

  async onClick() {
    if (this.props.description === undefined) {
      const data = (await fetch(`/data/events/by-id/${this.props.id}`).then(a =>
        a.json()
      )) as any | { error: string };

      if ("error" in data) {
        throw new Error(data.error);
      }

      const p = this.props;
      this.props.updateData(
        Object.assign(remapEvent(data), { day: p.day, title: p.title })
      );
    }
    this.props.toggle();
  }
}

class Category extends React.Component<CategoryData & CategoryProperties> {
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
        title = "Unknown category type: " + this.props.type;
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

    title = (this.props.open ? "▼  " : "▶  ") + title;

    return (
      <li className={this.props.type}>
        <span className="heading" onClick={this.onClick.bind(this)}>
          {title}
        </span>

        <ul className={this.props.open ? "open" : "closed"}>
          {this.props.events.map((event, index) => (
            <Event
              {...event}
              updateData={data =>
                this.props.updateEventData(this.props.index, index, data)
              }
              toggle={() => this.props.toggleEvent(this.props.index, index)}
              key={event.id + event.title}
            />
          ))}
          {this.props.subcategories.map(s => (
            <Category
              key={s.index.toString()}
              {...s}
              bounds={this.props.bounds}
              addSubcategory={this.props.addSubcategory}
              toggle={this.props.toggle}
              setLoading={this.props.setLoading}
              updateEventData={this.props.updateEventData}
              toggleEvent={this.props.toggleEvent}
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

    const getData = async (date: Moment, precision: CategoryType) => {
      const data = (await fetch(
        `/data/events/by-date/${date.toISOString()}/${precision}`
      ).then(a => a.json())) as { events: any[] } | { error: string };

      if ("error" in data) {
        throw new Error(data.error);
      }

      return data;
    };

    const getEventCount = async (date1: Moment, precision: CategoryType) => {
      let date2: Moment;
      switch (precision) {
        case CategoryType.Era:
          if (date1.year() < 0) {
            date1 = this.props.bounds.min.clone();
            date2 = moment.utc({year: 0, month: 1, day: 1});
          } else {
            date1 = moment.utc({year: 0, month: 1, day: 1});
            date2 = this.props.bounds.max.clone();
          }
          break;
        case CategoryType.Millennium:
          date2 = date1.clone().year(date1.year() + 1000);
          break;
        case CategoryType.Century:
          date2 = date1.clone().year(date1.year() + 100);
          break;
        case CategoryType.Decade:
          date2 = date1.clone().year(date1.year() + 10);
          break;
        case CategoryType.Year:
          date2 = date1.clone().year(date1.year() + 1);
          break;
        case CategoryType.Month:
          date2 = date1.clone().month(date1.month() + 1);
          break;
        case CategoryType.Day:
          date2 = date1.clone().day(date1.day() + 1);
          break;
        default:
          throw new Error("unsupported precision");
      }

      const data = (await fetch(
        `/data/events/count/${date1.toISOString()}/${date2.toISOString()}`
      ).then(a => a.json())) as { count: number } | { error: string };

      if ("error" in data) {
        throw new Error(data.error);
      }

      return data.count;
    }

    const eventData = await getData(date, this.props.type);
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

    const events = eventData.events.map(remapEvent);

    if (this.props.type !== "month" && events.length > 0) {
      addToSubcategories(null, events, true);
    }

    const tuple = <T extends any[]>(...data: T) => {
      return data;
    };

    const getValidDates = (dates: Moment[], type: CategoryType) => Promise.all(
      dates.map(date =>
        getEventCount(date, type).then(count => tuple(date, count))
      )
    ).then(ds => ds.filter(([_, c]) => c > 0).map(([d, _]) => d) );

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
      const dates = Array.from(Array(10), (_, i) => date.clone().year(date.year() + 100*i));
      const validDates = await getValidDates(dates, CategoryType.Century);

      for (const date of validDates) {
        addToSubcategories(date);
      }
    } else if (this.props.type === "century") {
      const dates = Array.from(Array(10), (_, i) => date.clone().year(date.year() + 10*i));
      const validDates = await getValidDates(dates, CategoryType.Decade);

      for (const date of validDates) {
        addToSubcategories(date);
      }
    } else if (this.props.type === "decade") {
      const dates = Array.from(Array(10), (_, i) => date.clone().year(date.year() + i));
      const validDates = await getValidDates(dates, CategoryType.Year);

      for (const date of validDates) {
        addToSubcategories(date);
      }
    } else if (this.props.type === "year") {
      const dates = Array.from(Array(12), (_, i) => date.clone().month(i));
      const dateEvents = await Promise.all(
        dates.map(date =>
          getData(date, CategoryType.Month).then(data => tuple(date, data))
        )
      );

      for (const [date, data] of dateEvents) {
        if (data.events.length !== 0) {
          addToSubcategories(date, data.events.map(remapEvent), true);
        }
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
  setLoading,
  updateEventData,
  toggleEvent
}: CategoryData & CategoryProperties) => (
  <ul>
    {subcategories.map(a => (
      <Category
        key={a.index.toString()}
        bounds={bounds}
        addSubcategory={addSubcategory}
        toggle={toggle}
        setLoading={setLoading}
        updateEventData={updateEventData}
        toggleEvent={toggleEvent}
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

  updateEventData(
    categoryIndex: number[],
    eventIndex: number,
    data: EventData
  ) {
    const { subtree, root } = this.getSubtree(categoryIndex);
    subtree.events[eventIndex] = data;
    this.setState({ root });
  }

  toggleEvent(categoryIndex: number[], eventIndex: number) {
    const { subtree, root } = this.getSubtree(categoryIndex);
    subtree.events[eventIndex].open = !subtree.events[eventIndex].open;
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
            updateEventData={this.updateEventData.bind(this)}
            toggleEvent={this.toggleEvent.bind(this)}
          />
        ) : null}
      </div>
    );
  }
}
export default App;
