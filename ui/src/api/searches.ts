import type { Search, SearchCriteria } from "../types";
import { apiClient } from "./client";

// Wire format of GET /searches (docs/SeachCriteria.Feature.md, section 8, SearchDto).
// Counts use the API's "saved"; the UI keeps "accepted".
interface SearchDto {
  id: string;
  title: string;
  criteria: Partial<SearchCriteria> & { keywords: string[] };
  status: "active";
  counts: { new: number; saved: number; rejected: number };
  createdAt: string;
  updatedAt: string;
}

function toSearch(dto: SearchDto): Search {
  const { criteria, counts } = dto;
  return {
    id: dto.id,
    title: dto.title,
    criteria: {
      keywords: criteria.keywords,
      excludeKeywords: criteria.excludeKeywords ?? [],
      priceMin: criteria.priceMin ?? null,
      priceMax: criteria.priceMax ?? null,
      location: criteria.location ?? null,
      description: criteria.description ?? "",
    },
    status: dto.status,
    counts: { new: counts.new, accepted: counts.saved, rejected: counts.rejected },
    createdAt: dto.createdAt,
  };
}

export async function fetchSearches(signal?: AbortSignal): Promise<Search[]> {
  const { data } = await apiClient.get<SearchDto[]>("/searches", { signal });
  return data.map(toSearch);
}

export interface NewSearch {
  title: string;
  criteria: Partial<SearchCriteria> & { keywords: string[] };
}

export async function createSearch(search: NewSearch): Promise<Search> {
  const { data } = await apiClient.post<SearchDto>("/searches", search);
  return toSearch(data);
}
