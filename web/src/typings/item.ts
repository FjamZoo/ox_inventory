export type ItemData = {
  name: string;
  size?: { width: number; height: number };
  label: string;
  stack: boolean;
  usable: boolean;
  close: boolean;
  count: number;
  description?: string;
  buttons?: string[];
  ammoName?: string;
  image?: string;
};
