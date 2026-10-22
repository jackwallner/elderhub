// Test-only service client. No network or real credentials.
export const calls: string[] = [];

export function createClient(_url: string, _key: string) {
  return {
    from(table: string) {
      const query = {
        select(_columns: string) { return query; },
        eq(_column: string, _value: unknown) { return query; },
        is(_column: string, _value: unknown) { return query; },
        in(_column: string, _values: string[]) {
          calls.push(`read:${table}`);
          return Promise.resolve({ data: [{ group_id: "another-family" }], error: null as { message: string } | null });
        },
        upsert(_rows: unknown, _options: unknown) {
          calls.push(`write:${table}`);
          return Promise.resolve({ error: null as { message: string } | null });
        },
      };
      return query;
    },
    rpc(name: string, _args?: unknown) {
      calls.push(`rpc:${name}`);
      return Promise.resolve({ data: name === "queue_check_in_notices" ? 1 : [], error: null as { message: string } | null });
    },
  };
}
