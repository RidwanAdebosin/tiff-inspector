import { describe, expect, it } from "vitest";
import { parseLocation, problems } from "./protocol";

describe("parseLocation", () => {
  it("parses the toplevel's line:col:endLine:endCol form", () => {
    expect(parseLocation("3:14:3:20")).toEqual({
      line: 3,
      col: 14,
      endLine: 3,
      endCol: 20,
    });
    expect(parseLocation(" 1:0:2:5\n")).toEqual({
      line: 1,
      col: 0,
      endLine: 2,
      endCol: 5,
    });
  });

  it("rejects malformed or inverted ranges", () => {
    expect(parseLocation("nope")).toBeNull();
    expect(parseLocation("0:1:0:2")).toBeNull();
    expect(parseLocation("4:0:2:0")).toBeNull();
  });
});

describe("problems", () => {
  it("pairs each location with the error printed after it, minus the header", () => {
    const result = {
      chunks: [
        { kind: "stdout" as const, text: "hello\n" },
        {
          kind: "stderr" as const,
          text: "Line 2, characters 14-20:\nError: This constant has type string\n",
        },
        { kind: "answer" as const, text: "val x : int = 2\n" },
        {
          kind: "stderr" as const,
          text: "Line 5, characters 0-3:\nError: Unbound value foo\n",
        },
      ],
      locations: [
        { loc: "2:14:2:20", chunkIndex: 1 },
        { loc: "5:0:5:3", chunkIndex: 3 },
        { loc: "garbage", chunkIndex: 3 },
      ],
    };
    expect(problems(result)).toEqual([
      {
        line: 2,
        col: 14,
        endLine: 2,
        endCol: 20,
        message: "Error: This constant has type string",
      },
      {
        line: 5,
        col: 0,
        endLine: 5,
        endCol: 3,
        message: "Error: Unbound value foo",
      },
    ]);
  });

  it("drops the echoed source line and caret from the message", () => {
    const result = {
      chunks: [
        {
          kind: "stderr" as const,
          text: 'Line 8, characters 19-30:\n8 | let answer : int = "forty-two"\n                       ^^^^^^^^^^^\nError: This constant has type string but an expression was expected of type\n         int\n',
        },
      ],
      locations: [{ loc: "8:19:8:30", chunkIndex: 0 }],
    };
    expect(problems(result)[0].message).toBe(
      "Error: This constant has type string but an expression was expected of type\n         int",
    );
  });

  it("falls back to a generic message when the chunk is missing", () => {
    expect(
      problems({ chunks: [], locations: [{ loc: "1:0:1:1", chunkIndex: 0 }] }),
    ).toEqual([{ line: 1, col: 0, endLine: 1, endCol: 1, message: "Error" }]);
  });
});
