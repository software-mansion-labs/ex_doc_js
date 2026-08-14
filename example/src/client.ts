/**
 * Options that configure how a client behaves.
 */
export interface ClientOpts {
  /** Number of retries before giving up on a failed send. */
  retries?: number;

  /** Callback invoked whenever the underlying transport opens or closes. */
  onStatusChange?: (connected: boolean) => void;
}

/**
 * A client for the example transport.
 *
 * Create one with {@link create}, then {@link connect} and {@link send}.
 */
export interface Client {
  /** Unique name for this client. */
  readonly name: string;

  /** The options the client was configured with. */
  readonly opts: ClientOpts;
}

/**
 * Creates a new client.
 *
 * When no options are given, sensible defaults are used instead. The returned
 * client is inert until `ExampleLib.connect/0` is called on it.
 *
 * @param name - Unique name for the client.
 * @param opts - Optional configuration.
 * @returns A configured, disconnected {@link Client}.
 */
export function create(name: string, opts?: ClientOpts): Client {
  return { name, opts: opts ?? {} };
}

/**
 * Opens the transport and marks the client connected.
 *
 * Safe to call more than once: subsequent calls are no-ops while already
 * connected. Must happen before {@link send}.
 *
 * @returns A promise that resolves once the connection is established.
 */
export async function connect(): Promise<void> {
  return void 0;
}

/**
 * Sends a message over the established transport.
 *
 * @param payload - The message body as a UTF-8 string.
 * @returns Resolves when the transport has accepted the message.
 *
 * @throws an `Error` when called before {@link connect}.
 */
export async function send(payload: string): Promise<void> {
  void payload;
}
