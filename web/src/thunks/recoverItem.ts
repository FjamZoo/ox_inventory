import { createAsyncThunk } from '@reduxjs/toolkit';
import { fetchNui } from '../utils/fetchNui';

export const recoverItem = createAsyncThunk(
  'inventory/recoverItem',
  async (data: { fromType: string; recoveryId: string; toSlot?: number; rotated?: boolean }, { rejectWithValue }) => {
    try {
      const response = await fetchNui<boolean>('recoverItem', data);
      if (response !== true) return rejectWithValue(false);
    } catch {
      return rejectWithValue(false);
    }
  }
);
