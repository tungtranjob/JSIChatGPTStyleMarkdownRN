/**
 * Codegen spec for the native markdown chat list.
 *
 * Everything that is expensive (markdown parsing, span building, text layout,
 * cell recycling, prefetching) lives on the native side. JS only owns the data.
 */
import type {HostComponent, ViewProps} from 'react-native';
import {
  codegenNativeCommands,
  codegenNativeComponent,
  type CodegenTypes,
} from 'react-native';


export type NativeMdMessage = Readonly<{
  /** Stable identity. Used for diffing + as the parse/layout cache key. */
  id: string;
  /** 'user' | 'assistant' */
  role: string;
  markdown: string;
  /**
   * True while tokens are still streaming in. Native throttles re-parsing of a
   * streaming message to one pass per frame and only re-lays-out its tail.
   */
  streaming?: boolean;
}>;

export interface NativeProps extends ViewProps {
  messages: ReadonlyArray<NativeMdMessage>;

  /** 'light' | 'dark' */
  colorScheme?: CodegenTypes.WithDefault<string, 'light'>;
  /** Base body font size in sp/pt. */
  fontSize?: CodegenTypes.WithDefault<CodegenTypes.Double, 16>;
  /** Extra bottom inset (e.g. for a composer bar), in dp/pt. */
  bottomInset?: CodegenTypes.WithDefault<CodegenTypes.Double, 0>;
  /** Extra top inset (e.g. for a header), in dp/pt. */
  topInset?: CodegenTypes.WithDefault<CodegenTypes.Double, 0>;
  /** Show the "loading older messages" spinner at the top of the list. */
  loadingOlder?: CodegenTypes.WithDefault<boolean, false>;
  /** How far (in dp/pt) from the start of the list `onStartReached` fires. */
  startReachedThreshold?: CodegenTypes.WithDefault<CodegenTypes.Double, 600>;
  /** How many rows ahead of the viewport get their text laid out in background. */
  prefetchRows?: CodegenTypes.WithDefault<CodegenTypes.Int32, 12>;
  /** Stick to the bottom when new content arrives and the user is already at the bottom. */
  autoScrollToBottom?: CodegenTypes.WithDefault<boolean, true>;

  /**
   * Fired when the user scrolls near the start of the list: load an older page.
   *
   * Named `onStartReached` rather than `onTopReached` on purpose: React Native
   * normalizes a C++ event name by prefixing "top", but skips names that already
   * start with "top", so an `onTopReached` prop dispatches `topReached` while the
   * JS view config registers `topTopReached` - and every event throws
   * "Unsupported top level event type".
   */
  onStartReached?: CodegenTypes.DirectEventHandler<Readonly<{oldestId: string}>>;
  onLinkPress?: CodegenTypes.DirectEventHandler<Readonly<{url: string}>>;
  onCodeCopy?: CodegenTypes.DirectEventHandler<Readonly<{language: string; code: string}>>;
  /** atBottom flips when the user scrolls away from / back to the bottom. */
  onAtBottomChange?: CodegenTypes.DirectEventHandler<Readonly<{atBottom: boolean}>>;
  /** Debug/telemetry: which flattened block range is on screen. */
  onVisibleRangeChange?: CodegenTypes.DirectEventHandler<
    Readonly<{firstIndex: CodegenTypes.Int32; lastIndex: CodegenTypes.Int32; blockCount: CodegenTypes.Int32}>
  >;
}

type ComponentType = HostComponent<NativeProps>;

interface NativeCommands {
  scrollToBottom: (viewRef: React.ElementRef<ComponentType>, animated: boolean) => void;
  scrollToMessage: (
    viewRef: React.ElementRef<ComponentType>,
    messageId: string,
    animated: boolean,
  ) => void;
}

export const Commands: NativeCommands = codegenNativeCommands<NativeCommands>({
  supportedCommands: ['scrollToBottom', 'scrollToMessage'],
});

export default codegenNativeComponent<NativeProps>('MdListView') as ComponentType;
