export interface QuoteItem {id:string;text:string;label:string}
export interface ConversationTurn {id:string;requestId:string;question:string;quotes:QuoteItem[];answer:string;reasoning?:string;status:string;error?:string;canRegenerate:boolean;canRetry:boolean;images?:{id:string;thumbnailURL:string;previewURL:string}[]}
export interface AssistantReference {id:string;sourceTurnId:string;sourceRequestId:string;text:string}
export interface ModelGroup {id:string;label:string;models:readonly {id:string;label:string}[]}
