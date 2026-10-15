export type ItemData = {
  name: string;
  label: string;
  stack: boolean;
  usable: boolean;
  close: boolean;
  count: number;
  size?: { width: number; height: number };
  description?: string;
  buttons?: string[];
  ammoName?: string;
  image?: string;
};
