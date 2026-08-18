export type MdRole = 'user' | 'assistant';

export type MdMessage = {
  id: string;
  role: MdRole;
  markdown: string;
  /** true while the assistant is still streaming this message */
  streaming?: boolean;
};

export type MdListHandle = {
  scrollToBottom: (animated?: boolean) => void;
  scrollToMessage: (messageId: string, animated?: boolean) => void;
};
