// Router payloads. ArkTS requires object literals to have a declared type, so
// navigation parameters travel as small classes rather than inline literals.

export class NoteRouteParams {
  id: string;

  constructor(id: string) {
    this.id = id;
  }
}

export class TagRouteParams {
  tagId: string;
  title: string;

  constructor(tagId: string, title: string) {
    this.tagId = tagId;
    this.title = title;
  }
}
